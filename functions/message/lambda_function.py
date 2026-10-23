"""WebSocket message and sendaudio route Lambda handler.

Includes:
- In-memory DynamoDB connections cache (TTL 3s) to reduce RCU costs by ~95%.
- Optional EventBridge/S3 archival (`ENABLE_AUDIO_ARCHIVAL`) to eliminate S3 PUT costs in live games.
- Room/Server isolation (`roomId`) so players on different servers don't hear each other.
- 3D Proximity filtering (`x, y, z, dimension` and `MAX_VOICE_DISTANCE`) to save outbound bandwidth.
"""

import base64
import json
import logging
import math
import os
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

import boto3
from botocore.exceptions import ClientError

# Configure logging for CloudWatch
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Environment variables (UPPER_CASE)
CONNECTIONS_TABLE_NAME = os.environ.get("CONNECTIONS_TABLE", "")
EVENT_BUS_NAME = os.environ.get("EVENT_BUS_NAME", "")
EVENT_SOURCE = os.environ.get("EVENT_SOURCE", "voice-chat")
DIRECT_BROADCAST = os.environ.get("DIRECT_BROADCAST", "false").lower() == "true"
ENABLE_AUDIO_ARCHIVAL = os.environ.get("ENABLE_AUDIO_ARCHIVAL", "true").lower() == "true"
ECHO_MODE = os.environ.get("ECHO_MODE", "false").lower() == "true"
MAX_AUDIO_BYTES = int(os.environ.get("MAX_AUDIO_BYTES", str(128 * 1024)))
CONNECTIONS_CACHE_TTL_SECONDS = float(
    os.environ.get("CONNECTIONS_CACHE_TTL_SECONDS", "3.0")
)
MAX_VOICE_DISTANCE = float(os.environ.get("MAX_VOICE_DISTANCE", "64.0"))

_dynamodbResource = None
_eventsClient = None
_apigwClients: Dict[str, Any] = {}

# In-memory cache of active connections for warm Lambda invocations
_cachedConnections: List[Dict[str, Any]] = []
_connectionsCacheExpiresAt: float = 0.0
_cachedTableName: str = ""


def invalidateConnectionsCache() -> None:
    """Clear the in-memory connections cache."""
    global _cachedConnections, _connectionsCacheExpiresAt
    _cachedConnections = []
    _connectionsCacheExpiresAt = 0.0


def getDynamodbTable() -> Any:
    """Return a cached DynamoDB Table resource for WebSocket connections."""
    global _dynamodbResource
    tableName = os.environ.get("CONNECTIONS_TABLE", CONNECTIONS_TABLE_NAME)
    if not tableName:
        raise ValueError("CONNECTIONS_TABLE environment variable not set")
    if _dynamodbResource is None:
        _dynamodbResource = boto3.resource("dynamodb")
    return _dynamodbResource.Table(tableName)


def getCachedConnections(connectionsTable: Any) -> List[Dict[str, Any]]:
    """Retrieve active connections from in-memory cache or scan DynamoDB when expired."""
    global _cachedConnections, _connectionsCacheExpiresAt, _cachedTableName

    tableName = os.environ.get("CONNECTIONS_TABLE", CONNECTIONS_TABLE_NAME)
    cacheTtl = float(
        os.environ.get(
            "CONNECTIONS_CACHE_TTL_SECONDS", str(CONNECTIONS_CACHE_TTL_SECONDS)
        )
    )
    now = time.monotonic()

    if (
        cacheTtl > 0
        and _cachedConnections
        and now < _connectionsCacheExpiresAt
        and _cachedTableName == tableName
    ):
        return list(_cachedConnections)

    items: List[Dict[str, Any]] = []
    scanKwargs: Dict[str, Any] = {
        "ProjectionExpression": "connectionId, roomId, position, dimension"
    }
    while True:
        scanResponse = connectionsTable.scan(**scanKwargs)
        items.extend(scanResponse.get("Items", []))
        lastKey = scanResponse.get("LastEvaluatedKey")
        if not lastKey:
            break
        scanKwargs["ExclusiveStartKey"] = lastKey

    _cachedConnections = items
    _connectionsCacheExpiresAt = now + cacheTtl
    _cachedTableName = tableName
    return list(_cachedConnections)


def getEventsClient() -> Any:
    """Return a cached EventBridge client."""
    global _eventsClient
    if _eventsClient is None:
        _eventsClient = boto3.client("events")
    return _eventsClient


def getApiGatewayManagementClient(event: Dict[str, Any]) -> Optional[Any]:
    """Create or retrieve a cached API Gateway Management API client for WebSocket communication."""
    requestContext = event.get("requestContext", {})
    domainName = requestContext.get("domainName")
    stage = requestContext.get("stage")
    if not domainName or not stage:
        return None
    endpointUrl = f"https://{domainName}/{stage}"
    if endpointUrl not in _apigwClients:
        _apigwClients[endpointUrl] = boto3.client(
            "apigatewaymanagementapi", endpoint_url=endpointUrl
        )
    return _apigwClients[endpointUrl]


def buildResponse(statusCode: int, body: Any) -> Dict[str, Any]:
    """Build an API Gateway proxy response dictionary."""
    serializedBody = body if isinstance(body, str) else json.dumps(body)
    return {
        "statusCode": statusCode,
        "body": serializedBody,
    }


def sendPongResponse(apigwClient: Any, connectionId: str) -> bool:
    """Send a pong response to a client's ping request."""
    try:
        responseMessage = {
            "action": "pong",
            "data": {
                "connectionId": connectionId,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            },
        }
        apigwClient.post_to_connection(
            ConnectionId=connectionId,
            Data=json.dumps(responseMessage),
        )
        return True
    except Exception as err:
        logger.error("Pong error for connection %s: %s", connectionId, err)
        return False


def validateAudioPayload(audioData: Optional[str]) -> Tuple[bool, str]:
    """Validate base64 audio payload presence, encoding, and size limits."""
    if not audioData or not isinstance(audioData, str):
        return False, "Missing audio data"
    try:
        decodedBytes = base64.b64decode(audioData, validate=True)
    except Exception as err:
        return False, f"Invalid base64 audio data: {err}"

    if len(decodedBytes) == 0:
        return False, "Empty audio payload"
    if len(decodedBytes) > MAX_AUDIO_BYTES:
        return (
            False,
            f"Audio payload exceeds maximum allowed size ({MAX_AUDIO_BYTES} bytes)",
        )
    return True, "Valid"


def isWithinProximity(
    senderPosition: Optional[Dict[str, Any]],
    senderDimension: Optional[str],
    targetItem: Dict[str, Any],
    maxDistance: float,
) -> bool:
    """Determine if a listener is within hearing distance in the same dimension."""
    if maxDistance <= 0 or not senderPosition:
        return True

    targetDimension = targetItem.get("dimension")
    if senderDimension and targetDimension and senderDimension != targetDimension:
        return False

    targetPosition = targetItem.get("position")
    if not isinstance(targetPosition, dict):
        return True

    try:
        dx = float(senderPosition.get("x", 0.0)) - float(targetPosition.get("x", 0.0))
        dy = float(senderPosition.get("y", 0.0)) - float(targetPosition.get("y", 0.0))
        dz = float(senderPosition.get("z", 0.0)) - float(targetPosition.get("z", 0.0))
        distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        return distance <= maxDistance
    except (TypeError, ValueError):
        return True


def broadcastAudioDirectly(
    apigwClient: Any,
    connectionsTable: Any,
    sourceConnectionId: str,
    audioData: str,
    author: str,
    timestamp: str,
    senderRoomId: Optional[str] = None,
    senderPosition: Optional[Dict[str, Any]] = None,
    senderDimension: Optional[str] = None,
    codec: str = "pcm",
) -> Dict[str, int]:
    """Fast-path broadcast of audio directly to active WebSocket connections in the same room/range."""
    items = getCachedConnections(connectionsTable)
    validItems = [item for item in items if "connectionId" in item]

    # Resolve sender's stored roomId if not provided in the message
    effectiveRoomId = senderRoomId
    if not effectiveRoomId:
        for item in validItems:
            if item["connectionId"] == sourceConnectionId:
                effectiveRoomId = item.get("roomId")
                break

    isEchoMode = os.environ.get("ECHO_MODE", str(ECHO_MODE)).lower() == "true"
    if len(validItems) == 1 and validItems[0]["connectionId"] == sourceConnectionId:
        isEchoMode = True

    maxDistance = float(
        os.environ.get("MAX_VOICE_DISTANCE", str(MAX_VOICE_DISTANCE))
    )

    outboundData: Dict[str, Any] = {
        "audio": audioData,
        "author": author,
        "timestamp": timestamp,
        "codec": codec,
        "status": "VALIDATED",
    }
    if senderPosition:
        outboundData["position"] = senderPosition

    outboundPayload = json.dumps({"action": "audio", "data": outboundData})

    stats = {
        "total": len(validItems),
        "sent": 0,
        "skippedRoomOrProximity": 0,
        "failed": 0,
        "staleRemoved": 0,
    }

    for item in validItems:
        targetConnId = item["connectionId"]
        if not isEchoMode and targetConnId == sourceConnectionId:
            continue

        # Filter by roomId when specified
        targetRoomId = item.get("roomId")
        if effectiveRoomId and targetRoomId and effectiveRoomId != targetRoomId:
            stats["skippedRoomOrProximity"] += 1
            continue

        # Filter by 3D proximity when coordinates are available
        if not isWithinProximity(
            senderPosition, senderDimension, item, maxDistance
        ):
            stats["skippedRoomOrProximity"] += 1
            continue

        try:
            apigwClient.post_to_connection(
                ConnectionId=targetConnId,
                Data=outboundPayload,
            )
            stats["sent"] += 1
        except Exception as err:
            if "GoneException" in str(err):
                try:
                    connectionsTable.delete_item(Key={"connectionId": targetConnId})
                    invalidateConnectionsCache()
                    stats["staleRemoved"] += 1
                except Exception as delErr:
                    logger.error(
                        "Failed to remove stale connection %s: %s", targetConnId, delErr
                    )
            else:
                stats["failed"] += 1
                logger.error("Failed to broadcast to %s: %s", targetConnId, err)

    return stats


def publishAudioEvent(
    messageBody: Dict[str, Any],
    websocketContext: Dict[str, str],
    timestamp: str,
    eventStatus: str = "PENDING",
) -> None:
    """Publish a SendAudioEvent to EventBridge and verify FailedEntryCount."""
    eventBusName = os.environ.get("EVENT_BUS_NAME", EVENT_BUS_NAME)
    eventSource = os.environ.get("EVENT_SOURCE", EVENT_SOURCE)

    detailPayload = {
        "event_id": str(uuid.uuid4()),
        "status": eventStatus,
        "message": messageBody,
        "timestamp": timestamp,
        "websocket_context": websocketContext,
    }

    entry: Dict[str, Any] = {
        "Source": eventSource,
        "DetailType": "SendAudioEvent",
        "Detail": json.dumps(detailPayload),
    }
    if eventBusName:
        entry["EventBusName"] = eventBusName

    response = getEventsClient().put_events(Entries=[entry])
    if response.get("FailedEntryCount", 0) > 0:
        entries = response.get("Entries", [])
        raise RuntimeError(f"EventBridge put_events failed: {entries}")


def handleUpdateState(
    connectionsTable: Any,
    connectionId: str,
    messageBody: Dict[str, Any],
) -> Dict[str, Any]:
    """Update player roomId, 3D position (x, y, z), or dimension in DynamoDB."""
    roomId = messageBody.get("roomId") or messageBody.get("room")
    position = messageBody.get("position")
    dimension = messageBody.get("dimension")

    updateParts: List[str] = []
    exprValues: Dict[str, Any] = {}

    if roomId:
        updateParts.append("roomId = :r")
        exprValues[":r"] = str(roomId)[:64]
    if isinstance(position, dict):
        updateParts.append("#pos = :p")
        exprValues[":p"] = {
            "x": Decimal(str(position.get("x", 0))),
            "y": Decimal(str(position.get("y", 0))),
            "z": Decimal(str(position.get("z", 0))),
        }
    if dimension:
        updateParts.append("dimension = :d")
        exprValues[":d"] = str(dimension)[:64]

    if not updateParts:
        return buildResponse(400, {"error": "No state fields provided"})

    updateKwargs: Dict[str, Any] = {
        "Key": {"connectionId": connectionId},
        "UpdateExpression": "SET " + ", ".join(updateParts),
        "ExpressionAttributeValues": exprValues,
    }
    if isinstance(position, dict):
        updateKwargs["ExpressionAttributeNames"] = {"#pos": "position"}

    connectionsTable.update_item(**updateKwargs)
    invalidateConnectionsCache()
    return buildResponse(200, {"message": "Player state updated"})


def handleMessage(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    """Route and process incoming WebSocket messages ('ping', 'updatestate', 'sendaudio')."""
    requestContext = event.get("requestContext", {})
    sourceConnectionId = requestContext.get("connectionId")
    domainName = requestContext.get("domainName")
    stage = requestContext.get("stage")

    if not sourceConnectionId or not domainName or not stage:
        return buildResponse(400, "Missing connection information")

    try:
        connectionsTable = getDynamodbTable()
    except ValueError:
        return buildResponse(500, "Server configuration error")

    try:
        rawBody = event.get("body") or "{}"
        messageBody = json.loads(rawBody)
    except json.JSONDecodeError:
        return buildResponse(400, "Invalid JSON format")

    action = messageBody.get("action")
    if not action:
        return buildResponse(400, "No action specified")

    if action == "updatestate":
        try:
            return handleUpdateState(connectionsTable, sourceConnectionId, messageBody)
        except Exception as err:
            logger.error("Error updating state for %s: %s", sourceConnectionId, err)
            return buildResponse(500, {"error": "State update failed"})

    apigwClient = getApiGatewayManagementClient(event)
    if not apigwClient:
        return buildResponse(500, "API Gateway client initialization failed")

    if action == "ping":
        if sendPongResponse(apigwClient, sourceConnectionId):
            return buildResponse(200, {"message": "Pong sent"})
        return buildResponse(500, {"error": "Pong failed"})

    if action == "sendaudio":
        audioData = messageBody.get("data")
        author = messageBody.get("author", "Anonymous")
        roomId = messageBody.get("roomId") or messageBody.get("room")
        position = messageBody.get("position")
        dimension = messageBody.get("dimension")
        codec = messageBody.get("codec", "pcm")

        isValid, validationMsg = validateAudioPayload(audioData)
        if not isValid:
            logger.warning(
                "Invalid audio payload from %s: %s", sourceConnectionId, validationMsg
            )
            return buildResponse(400, {"error": validationMsg})

        timestamp = datetime.now(timezone.utc).isoformat()
        websocketContext = {
            "domain_name": domainName,
            "stage": stage,
            "connection_id": sourceConnectionId,
        }

        directBroadcastEnabled = (
            os.environ.get("DIRECT_BROADCAST", str(DIRECT_BROADCAST)).lower() == "true"
        )
        archivalEnabled = (
            os.environ.get(
                "ENABLE_AUDIO_ARCHIVAL", str(ENABLE_AUDIO_ARCHIVAL)
            ).lower()
            == "true"
        )

        try:
            broadcastStats = None
            if directBroadcastEnabled:
                broadcastStats = broadcastAudioDirectly(
                    apigwClient=apigwClient,
                    connectionsTable=connectionsTable,
                    sourceConnectionId=sourceConnectionId,
                    audioData=audioData,
                    author=author,
                    timestamp=timestamp,
                    senderRoomId=roomId,
                    senderPosition=position if isinstance(position, dict) else None,
                    senderDimension=dimension,
                    codec=codec,
                )

            # Publish to EventBridge if archival is enabled OR if direct broadcast is disabled
            if archivalEnabled or not directBroadcastEnabled:
                publishAudioEvent(
                    messageBody=messageBody,
                    websocketContext=websocketContext,
                    timestamp=timestamp,
                    eventStatus="BROADCASTED" if directBroadcastEnabled else "PENDING",
                )

            logger.info("Audio processed for %s (archival=%s)", sourceConnectionId, archivalEnabled)

            responsePayload: Dict[str, Any] = {"message": "Audio event sent"}
            if broadcastStats is not None:
                responsePayload["broadcast"] = broadcastStats
            return buildResponse(200, responsePayload)
        except ClientError as err:
            logger.error("AWS ClientError processing sendaudio: %s", err)
            return buildResponse(500, "Event processing failed")
        except Exception as err:
            logger.error("Error processing sendaudio: %s", err)
            return buildResponse(500, "Event processing failed")

    return buildResponse(400, {"error": f"Unhandled action: {action}"})


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda entry point for WebSocket messages."""
    return handleMessage(event, context)
