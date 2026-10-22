"""WebSocket $connect route Lambda handler."""

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Environment variables (UPPER_CASE)
CONNECTIONS_TABLE_NAME = os.environ.get("CONNECTIONS_TABLE", "")
CONNECTION_TTL_SECONDS = int(os.environ.get("CONNECTION_TTL_SECONDS", "86400"))

_dynamodbResource = None


def getDynamodbTable() -> Any:
    """Return a cached DynamoDB Table resource for WebSocket connections."""
    global _dynamodbResource
    tableName = os.environ.get("CONNECTIONS_TABLE", CONNECTIONS_TABLE_NAME)
    if not tableName:
        raise ValueError(
            "DynamoDB connections table name not set in environment variables (CONNECTIONS_TABLE)"
        )
    if _dynamodbResource is None:
        _dynamodbResource = boto3.resource("dynamodb")
    return _dynamodbResource.Table(tableName)


def buildResponse(statusCode: int, body: Any) -> Dict[str, Any]:
    """Build an API Gateway proxy response dictionary."""
    serializedBody = body if isinstance(body, str) else json.dumps(body)
    return {
        "statusCode": statusCode,
        "body": serializedBody,
    }


def handleConnect(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    """Process a new WebSocket connection and store its metadata in DynamoDB."""
    logger.info("Received connect event: %s", json.dumps(event))

    requestContext = event.get("requestContext", {})
    connectionId = requestContext.get("connectionId")
    domainName = requestContext.get("domainName")
    stage = requestContext.get("stage")

    if not connectionId:
        logger.error("Connection ID not found in event")
        return buildResponse(400, "Connection ID not found.")

    try:
        connectionsTable = getDynamodbTable()
    except ValueError as err:
        logger.error("Configuration error: %s", err)
        return buildResponse(500, "Server configuration error.")

    currentTimestamp = datetime.now(timezone.utc).isoformat()
    ttlEpoch = int(time.time()) + CONNECTION_TTL_SECONDS

    connectionItem: Dict[str, Any] = {
        "connectionId": connectionId,
        "connectedAt": currentTimestamp,
        "domain": domainName,
        "stage": stage,
        "ttl": ttlEpoch,
    }

    try:
        logger.info("Storing connection item: %s", json.dumps(connectionItem))
        connectionsTable.put_item(Item=connectionItem)
        logger.info("Connection %s stored successfully.", connectionId)
        return buildResponse(200, "Connected.")
    except ClientError as err:
        logger.error("DynamoDB error storing connection %s: %s", connectionId, err)
        return buildResponse(500, f"Failed to connect: {err}")
    except Exception as err:
        logger.error("Unexpected error storing connection %s: %s", connectionId, err)
        return buildResponse(500, f"Failed to connect: {err}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda entry point for the WebSocket $connect route."""
    return handleConnect(event, context)
