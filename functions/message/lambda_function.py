"""WebSocket message and sendaudio route Lambda handler."""

import base64
import json
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

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
ECHO_MODE = os.environ.get("ECHO_MODE", "false").lower() == "true"
MAX_AUDIO_BYTES = int(os.environ.get("MAX_AUDIO_BYTES", str(128 * 1024)))

_dynamodbResource = None
_eventsClient = None
_apigwClients: Dict[str, Any] = {}


def getDynamodbTable() -> Any:
    """Return a cached DynamoDB Table resource for WebSocket connections."""
    global _dynamodbResource
    tableName = os.environ.get("CONNECTIONS_TABLE", CONNECTIONS_TABLE_NAME)
    if not tableName:
        raise ValueError("CONNECTIONS_TABLE environment variable not set")
    if _dynamodbResource is None:
        _dynamodbResource = boto3.resource("dynamodb")
    return _dynamodbResource.Table(tableName)


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


def broadcastAudioDirectly(
    apigwClient: Any,
    connectionsTable: Any,
    sourceConnectionId: str,
    audioData: str,
    author: str,
    timestamp: str,
) -> Dict[str, int]:
    """Fast-path broadcast of audio directly to active WebSocket connections."""
    scanResponse = connectionsTable.scan(ProjectionExpression="connectionId")
    items = scanResponse.get("Items", [])
    connectionIds = [item["connectionId"] for item in items if "connectionId" in item]

    isEchoMode = os.environ.get("ECHO_MODE", str(ECHO_MODE)).lower() == "true"
    if len(connectionIds) == 1 and connectionIds[0] == sourceConnectionId:
        isEchoMode = True

    outboundPayload = json.dumps(
        {
            "action": "audio",
            "data": {
                "audio": audioData,
                "author": author,
                "timestamp": timestamp,
                "status": "VALIDATED",
            },
        }
    )

    stats = {"total": len(connectionIds), "sent": 0, "failed": 0, "staleRemoved": 0}
    for targetConnId in connectionIds:
        if not isEchoMode and targetConnId == sourceConnectionId:
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


def handleMessage(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    """Route and process incoming WebSocket messages ('ping' and 'sendaudio')."""
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
                )

            publishAudioEvent(
                messageBody=messageBody,
                websocketContext=websocketContext,
                timestamp=timestamp,
                eventStatus="BROADCASTED" if directBroadcastEnabled else "PENDING",
            )
            logger.info("Audio event sent from %s", sourceConnectionId)

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
