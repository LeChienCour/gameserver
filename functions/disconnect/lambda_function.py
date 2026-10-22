"""WebSocket $disconnect route Lambda handler."""

import json
import logging
import os
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Environment variables (UPPER_CASE)
CONNECTIONS_TABLE_NAME = os.environ.get("CONNECTIONS_TABLE", "")

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


def handleDisconnect(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    """Process a WebSocket disconnection and remove the connection record from DynamoDB."""
    logger.info("Received disconnect event: %s", json.dumps(event))

    requestContext = event.get("requestContext", {})
    connectionId = requestContext.get("connectionId")

    if not connectionId:
        logger.error("Connection ID not found in event")
        return buildResponse(400, "Connection ID not found.")

    try:
        connectionsTable = getDynamodbTable()
    except ValueError as err:
        logger.error("Configuration error: %s", err)
        return buildResponse(500, "Server configuration error.")

    try:
        deleteResponse = connectionsTable.delete_item(
            Key={"connectionId": connectionId},
            ReturnValues="ALL_OLD",
        )
        deletedAttributes = deleteResponse.get("Attributes")
        if deletedAttributes:
            logger.info(
                "Successfully deleted connection %s",
                connectionId,
            )
        else:
            logger.warning("No connection found to delete for ID: %s", connectionId)

        return buildResponse(200, "Disconnected.")
    except ClientError as err:
        logger.error("DynamoDB error deleting connection %s: %s", connectionId, err)
        return buildResponse(500, f"Failed to disconnect: {err}")
    except Exception as err:
        logger.error("Unexpected error deleting connection %s: %s", connectionId, err)
        return buildResponse(500, f"Failed to disconnect: {err}")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda entry point for the WebSocket $disconnect route."""
    return handleDisconnect(event, context)
