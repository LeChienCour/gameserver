"""Audio validation and WebSocket broadcast Lambda handler."""

import base64
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import boto3

# Configure logging for CloudWatch
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Environment variables (UPPER_CASE)
CONNECTIONS_TABLE_NAME = os.environ.get("CONNECTIONS_TABLE", "")
AUDIO_BUCKET_NAME = os.environ.get("AUDIO_BUCKET", "")
MIN_AUDIO_BYTES = int(os.environ.get("MIN_AUDIO_BYTES", "1024"))
MAX_AUDIO_BYTES = int(os.environ.get("MAX_AUDIO_BYTES", str(128 * 1024)))

_dynamodbClient = None
_s3Client = None
_apigwClients: Dict[str, Any] = {}


def getDynamodbClient() -> Any:
    """Return a cached DynamoDB client."""
    global _dynamodbClient
    if _dynamodbClient is None:
        _dynamodbClient = boto3.client("dynamodb")
    return _dynamodbClient


def getS3Client() -> Any:
    """Return a cached S3 client."""
    global _s3Client
    if _s3Client is None:
        _s3Client = boto3.client("s3")
    return _s3Client


def getApiClient(endpointUrl: str) -> Any:
    """Create or retrieve a cached API Gateway Management API client keyed by endpointUrl."""
    if endpointUrl not in _apigwClients:
        try:
            _apigwClients[endpointUrl] = boto3.client(
                "apigatewaymanagementapi",
                endpoint_url=endpointUrl,
            )
        except Exception as err:
            logger.error("API Gateway client error for %s: %s", endpointUrl, err)
            raise
    return _apigwClients[endpointUrl]


def fetchAllConnectionIds(tableName: str) -> List[str]:
    """Scan DynamoDB with pagination support and return all active connectionIds."""
    ddbClient = getDynamodbClient()
    connections: List[str] = []
    scanKwargs: Dict[str, Any] = {
        "TableName": tableName,
        "ProjectionExpression": "connectionId",
    }

    while True:
        response = ddbClient.scan(**scanKwargs)
        for item in response.get("Items", []):
            connId = item.get("connectionId", {}).get("S")
            if connId:
                connections.append(connId)
            else:
                logger.warning("Invalid connection item format: %s", item)

        lastEvaluatedKey = response.get("LastEvaluatedKey")
        if not lastEvaluatedKey:
            break
        scanKwargs["ExclusiveStartKey"] = lastEvaluatedKey

    return connections


def resolveAudioData(
    message: Dict[str, Any], s3Key: Optional[str]
) -> Optional[str]:
    """Resolve base64 audio data from the event message or fallback to S3 object."""
    inlineData = message.get("data")
    if inlineData and isinstance(inlineData, str):
        return inlineData

    audioBucket = os.environ.get("AUDIO_BUCKET", AUDIO_BUCKET_NAME)
    if s3Key and audioBucket:
        try:
            s3Obj = getS3Client().get_object(Bucket=audioBucket, Key=s3Key)
            rawBytes = s3Obj["Body"].read()
            return base64.b64encode(rawBytes).decode("utf-8")
        except Exception as err:
            logger.error("Failed to load audio from S3 (%s/%s): %s", audioBucket, s3Key, err)
            return None
    return None


def validateAudioFormat(audioData: str) -> Tuple[bool, str]:
    """Validate base64 encoding and byte size bounds of the audio data."""
    try:
        decodedData = base64.b64decode(audioData, validate=True)
        if len(decodedData) < MIN_AUDIO_BYTES:
            return False, "Audio data too small"
        if len(decodedData) > MAX_AUDIO_BYTES:
            return False, "Audio data too large"
        return True, "Valid audio data"
    except Exception as err:
        return False, f"Invalid audio data: {err}"


def broadcastAudio(
    connections: List[str],
    audioData: str,
    author: str,
    connectionId: str,
    endpointUrl: str,
) -> Tuple[Dict[str, Any], int, int, int]:
    """Broadcast validated audio data to all connected clients and clean up stale connections."""
    apiClient = getApiClient(endpointUrl)
    ddbClient = getDynamodbClient()
    connectionsTable = os.environ.get("CONNECTIONS_TABLE", CONNECTIONS_TABLE_NAME)

    message = {
        "action": "audio",
        "data": {
            "audio": audioData,
            "author": author,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "VALIDATED",
        },
    }

    messageJson = json.dumps(message)
    successfulBroadcasts = 0
    failedBroadcasts = 0
    deletedConnections = 0

    isEchoMode = os.environ.get("ECHO_MODE", "false").lower() == "true"
    singleConnection = len(connections) == 1 and connections[0] == connectionId

    if singleConnection:
        isEchoMode = True
        logger.info("Single connection detected, forcing echo mode")

    logger.info(
        "Broadcasting to %d connections (Echo mode: %s)",
        len(connections),
        isEchoMode,
    )

    for conn in connections:
        shouldBroadcast = isEchoMode or conn != connectionId
        if not shouldBroadcast:
            logger.info("Skipping source connection %s", conn)
            continue

        try:
            apiClient.post_to_connection(
                Data=messageJson,
                ConnectionId=conn,
            )
            successfulBroadcasts += 1
        except Exception as err:
            errorMsg = str(err)
            if "GoneException" in errorMsg:
                try:
                    ddbClient.delete_item(
                        TableName=connectionsTable,
                        Key={"connectionId": {"S": conn}},
                    )
                    deletedConnections += 1
                    logger.info("Deleted stale connection: %s", conn)
                except Exception as delErr:
                    logger.error("Connection deletion error: %s", delErr)
            else:
                failedBroadcasts += 1
                logger.error("Broadcast error for %s: %s", conn, errorMsg)

    logger.info(
        "Broadcast complete - Total: %d, Success: %d, Failed: %d, Deleted: %d, Echo mode: %s",
        len(connections),
        successfulBroadcasts,
        failedBroadcasts,
        deletedConnections,
        isEchoMode,
    )
    return message, successfulBroadcasts, failedBroadcasts, deletedConnections


def buildResponse(statusCode: int, body: Dict[str, Any]) -> Dict[str, Any]:
    """Build a JSON response dictionary."""
    return {
        "statusCode": statusCode,
        "body": json.dumps(body),
    }


def handleValidateAudio(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    """Validate processed audio events and broadcast to active WebSocket connections."""
    try:
        connectionsTable = os.environ.get("CONNECTIONS_TABLE", CONNECTIONS_TABLE_NAME)
        if not connectionsTable:
            logger.error("CONNECTIONS_TABLE environment variable not set")
            return buildResponse(500, {"error": "Server configuration error"})

        try:
            connections = fetchAllConnectionIds(connectionsTable)
            logger.info("Found %d active connections", len(connections))
            if not connections:
                return buildResponse(200, {"message": "No active connections"})
        except Exception as err:
            logger.error("DynamoDB scan error: %s", err)
            return buildResponse(500, {"error": "Database error"})

        detail = event.get("detail")
        if not isinstance(detail, dict):
            logger.error("Invalid event structure: %s", event)
            return buildResponse(400, {"error": "Invalid event structure"})

        message = detail.get("message", {})
        websocketContext = detail.get("websocket_context", {})
        s3Key = detail.get("s3_key")

        audioData = resolveAudioData(message, s3Key)

        requiredFields = {
            "status": detail.get("status"),
            "audio_data": audioData,
            "author": message.get("author"),
            "connection_id": websocketContext.get("connection_id"),
            "domain_name": websocketContext.get("domain_name"),
            "stage": websocketContext.get("stage"),
        }

        missingFields = [
            field for field, value in requiredFields.items() if not value
        ]
        if missingFields:
            logger.error("Missing required fields: %s", missingFields)
            return buildResponse(
                400, {"error": f"Missing fields: {', '.join(missingFields)}"}
            )

        author = str(requiredFields["author"])
        connectionId = str(requiredFields["connection_id"])
        endpointUrl = (
            f"https://{requiredFields['domain_name']}/{requiredFields['stage']}"
        )

        isValid, validationMessage = validateAudioFormat(str(audioData))
        if not isValid:
            logger.error("Audio validation failed: %s", validationMessage)
            return buildResponse(400, {"error": validationMessage})

        try:
            _, successes, failures, deletions = broadcastAudio(
                connections=connections,
                audioData=str(audioData),
                author=author,
                connectionId=connectionId,
                endpointUrl=endpointUrl,
            )

            return buildResponse(
                200,
                {
                    "message": "Audio broadcast complete",
                    "statistics": {
                        "total_connections": len(connections),
                        "successful": successes,
                        "failed": failures,
                        "deleted": deletions,
                    },
                },
            )
        except Exception as err:
            logger.error("Broadcast error: %s", err)
            return buildResponse(500, {"error": "Broadcast failed"})

    except Exception as err:
        logger.error("Validation error: %s", err)
        return buildResponse(500, {"error": str(err)})


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda entry point for audio validation and broadcast."""
    return handleValidateAudio(event, context)
