"""Audio processing and S3 archival Lambda handler."""

import base64
import json
import logging
import os
import re
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import boto3

# Configure logging for CloudWatch
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Environment variables (UPPER_CASE)
AUDIO_BUCKET_NAME = os.environ.get("AUDIO_BUCKET", "")
EVENT_BUS_NAME = os.environ.get("EVENT_BUS_NAME", "")
EVENT_SOURCE = os.environ.get("EVENT_SOURCE", "voice-chat")

_s3Client = None
_eventbridgeClient = None


def getS3Client() -> Any:
    """Return a cached S3 client."""
    global _s3Client
    if _s3Client is None:
        _s3Client = boto3.client("s3")
    return _s3Client


def getEventbridgeClient() -> Any:
    """Return a cached EventBridge client."""
    global _eventbridgeClient
    if _eventbridgeClient is None:
        _eventbridgeClient = boto3.client("events")
    return _eventbridgeClient


def validateEnvVars() -> str:
    """Validate that required environment variables are set and return AUDIO_BUCKET."""
    requiredVars = ["AUDIO_BUCKET"]
    missingVars = [var for var in requiredVars if not os.environ.get(var)]
    if missingVars:
        raise ValueError(
            f"Missing required environment variables: {', '.join(missingVars)}"
        )
    return os.environ["AUDIO_BUCKET"]


def sanitizeAuthor(author: str) -> str:
    """Sanitize author identifier to prevent S3 key traversal or invalid characters."""
    cleaned = re.sub(r"[^a-zA-Z0-9_-]", "_", author or "Anonymous")
    return cleaned[:64] or "Anonymous"


def getWebsocketContext(event: Dict[str, Any]) -> Optional[Dict[str, Optional[str]]]:
    """Extract WebSocket context from either direct WebSocket or EventBridge events."""
    if "requestContext" in event:
        requestContext = event.get("requestContext", {})
        return {
            "domain_name": requestContext.get("domainName"),
            "stage": requestContext.get("stage"),
            "connection_id": requestContext.get("connectionId"),
        }
    if "detail" in event and isinstance(event.get("detail"), dict):
        detail = event["detail"]
        return detail.get("websocket_context", {})
    return None


def getAudioData(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Extract and decode audio data from either WebSocket or EventBridge events."""
    if "detail" in event and isinstance(event.get("detail"), dict):
        detail = event["detail"]
        message = detail.get("message", {})
        rawAudio = message.get("data")
        author = message.get("author", "Anonymous")
    else:
        try:
            body = json.loads(event.get("body") or "{}")
            rawAudio = body.get("data")
            author = body.get("author", "Anonymous")
        except json.JSONDecodeError as err:
            logger.error("Invalid JSON in WebSocket message: %s", err)
            return None

    if not rawAudio or not isinstance(rawAudio, str):
        return None

    try:
        decodedBytes = base64.b64decode(rawAudio, validate=True)
        if not decodedBytes:
            return None
        return {
            "audio_data": rawAudio,
            "decoded_bytes": decodedBytes,
            "author": author,
        }
    except Exception as err:
        logger.error("Invalid base64 audio data: %s", err)
        return None


def buildS3Key(author: str, nowUtc: Optional[datetime] = None) -> str:
    """Build a collision-free S3 key using microsecond timestamps and a short UUID."""
    currentTime = nowUtc or datetime.now(timezone.utc)
    safeAuthor = sanitizeAuthor(author)
    timestampStr = currentTime.strftime("%Y%m%d_%H%M%S_%f")
    uniqueSuffix = uuid.uuid4().hex[:8]
    return f"audio/{safeAuthor}/{timestampStr}_{uniqueSuffix}.pcm"


def buildResponse(statusCode: int, body: Dict[str, Any]) -> Dict[str, Any]:
    """Build a JSON response dictionary."""
    return {
        "statusCode": statusCode,
        "body": json.dumps(body),
    }


def handleProcessAudio(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    """Store incoming PCM audio in S3 and publish a PROCESSED event to EventBridge."""
    try:
        audioBucket = validateEnvVars()

        wsContext = getWebsocketContext(event)
        if not wsContext or not all(
            [
                wsContext.get("domain_name"),
                wsContext.get("stage"),
                wsContext.get("connection_id"),
            ]
        ):
            errorMsg = (
                f"Missing WebSocket context fields: "
                f"{list(wsContext.keys()) if wsContext else 'None'}"
            )
            logger.error(errorMsg)
            return buildResponse(400, {"error": errorMsg})

        audioInfo = getAudioData(event)
        if not audioInfo:
            return buildResponse(400, {"error": "Invalid or missing audio data"})

        nowUtc = datetime.now(timezone.utc)
        s3Key = buildS3Key(audioInfo["author"], nowUtc)

        try:
            getS3Client().put_object(
                Bucket=audioBucket,
                Key=s3Key,
                Body=audioInfo["decoded_bytes"],
                ContentType="audio/pcm",
                Metadata={
                    "author": sanitizeAuthor(audioInfo["author"]),
                    "connection_id": str(wsContext["connection_id"]),
                    "timestamp": nowUtc.isoformat(),
                },
            )
            logger.info("Audio stored: %s", s3Key)
        except Exception as err:
            logger.error("S3 storage error: %s", err)
            return buildResponse(500, {"error": "Error storing audio"})

        # Check if message was already broadcasted on the fast path
        incomingStatus = (
            event.get("detail", {}).get("status", "PENDING")
            if isinstance(event.get("detail"), dict)
            else "PENDING"
        )
        if incomingStatus == "BROADCASTED":
            logger.info(
                "Audio %s was already broadcasted via fast-path; skipping validation event",
                s3Key,
            )
            return buildResponse(
                200,
                {
                    "message": "Audio archived",
                    "s3_key": s3Key,
                },
            )

        try:
            eventDetail = {
                "status": "PROCESSED",
                "message": {
                    "action": "sendaudio",
                    "data": audioInfo["audio_data"],
                    "author": audioInfo["author"],
                },
                "websocket_context": wsContext,
                "s3_key": s3Key,
                "timestamp": nowUtc.isoformat(),
            }

            eventEntry: Dict[str, Any] = {
                "Source": os.environ.get("EVENT_SOURCE", EVENT_SOURCE),
                "DetailType": "SendAudioEvent",
                "Detail": json.dumps(eventDetail),
            }
            eventBusName = os.environ.get("EVENT_BUS_NAME", EVENT_BUS_NAME)
            if eventBusName:
                eventEntry["EventBusName"] = eventBusName

            putResponse = getEventbridgeClient().put_events(Entries=[eventEntry])
            if putResponse.get("FailedEntryCount", 0) > 0:
                raise RuntimeError(
                    f"EventBridge failed entries: {putResponse.get('Entries')}"
                )

            logger.info("Audio validation event sent for %s", s3Key)
            return buildResponse(
                200,
                {
                    "message": "Audio processed",
                    "s3_key": s3Key,
                },
            )
        except Exception as err:
            logger.error("EventBridge error: %s", err)
            return buildResponse(500, {"error": "Error sending validation event"})

    except Exception as err:
        logger.error("Process audio error: %s", err)
        return buildResponse(500, {"error": str(err)})


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda entry point for audio processing."""
    return handleProcessAudio(event, context)
