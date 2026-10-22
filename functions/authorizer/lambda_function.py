"""WebSocket $connect Lambda Authorizer handler.

Validates the client API key against AWS Systems Manager Parameter Store (cached in memory)
or an environment variable fallback before allowing the WebSocket handshake.
"""

import hmac
import json
import logging
import os
import time
from typing import Any, Dict, Optional

import boto3

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# Environment variables (UPPER_CASE)
STAGE = os.environ.get("STAGE", "dev")
API_KEY_SSM_PARAMETER = os.environ.get(
    "API_KEY_SSM_PARAMETER", f"/game-server/{STAGE}/websocket/api-key"
)
EXPECTED_API_KEY_ENV = os.environ.get("EXPECTED_API_KEY", "")
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "300"))

_ssmClient = None
_cachedApiKey: Optional[str] = None
_cacheExpiresAt: float = 0.0


def getSsmClient() -> Any:
    """Return a cached SSM client."""
    global _ssmClient
    if _ssmClient is None:
        _ssmClient = boto3.client("ssm")
    return _ssmClient


def getExpectedApiKey() -> Optional[str]:
    """Retrieve the expected WebSocket API key from cache, env, or SSM Parameter Store."""
    global _cachedApiKey, _cacheExpiresAt

    envOverride = os.environ.get("EXPECTED_API_KEY", EXPECTED_API_KEY_ENV)
    if envOverride:
        return envOverride

    now = time.time()
    if _cachedApiKey and now < _cacheExpiresAt:
        return _cachedApiKey

    paramName = os.environ.get("API_KEY_SSM_PARAMETER", API_KEY_SSM_PARAMETER)
    try:
        response = getSsmClient().get_parameter(
            Name=paramName, WithDecryption=True
        )
        parameterValue = response.get("Parameter", {}).get("Value")
        if parameterValue:
            _cachedApiKey = parameterValue
            _cacheExpiresAt = now + CACHE_TTL_SECONDS
            return _cachedApiKey
    except Exception as err:
        logger.error("Failed to fetch API key from SSM (%s): %s", paramName, err)

    return _cachedApiKey


def extractClientApiKey(event: Dict[str, Any]) -> Optional[str]:
    """Extract the API key from headers (case-insensitive) or queryStringParameters."""
    headers = event.get("headers") or {}
    if isinstance(headers, dict):
        for key, value in headers.items():
            if key.lower() == "x-api-key" and value:
                return str(value)

    queryParams = event.get("queryStringParameters") or {}
    if isinstance(queryParams, dict):
        for key in ("x-api-key", "api_key", "apiKey"):
            if queryParams.get(key):
                return str(queryParams[key])

    return None


def generateIamPolicy(
    principalId: str,
    effect: str,
    resource: str,
    context: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    """Generate an IAM policy document for API Gateway WebSocket Custom Authorizer."""
    policyDocument: Dict[str, Any] = {
        "principalId": principalId,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": resource,
                }
            ],
        },
    }
    if context:
        policyDocument["context"] = context
    return policyDocument


def handleAuthorize(event: Dict[str, Any], context: Any = None) -> Dict[str, Any]:
    """Validate incoming WebSocket $connect request and return an IAM policy."""
    methodArn = event.get("methodArn", "*")
    clientKey = extractClientApiKey(event)

    if not clientKey:
        logger.warning("Rejected WebSocket connection: missing x-api-key")
        raise PermissionError("Unauthorized")

    expectedKey = getExpectedApiKey()
    if not expectedKey:
        logger.error("Expected API key could not be resolved from configuration")
        return generateIamPolicy("unauthorized", "Deny", methodArn)

    if hmac.compare_digest(clientKey.encode("utf-8"), expectedKey.encode("utf-8")):
        logger.info("Authorized WebSocket connection request")
        return generateIamPolicy(
            principalId="voice-chat-client",
            effect="Allow",
            resource=methodArn,
            context={"authenticated": "true"},
        )

    logger.warning("Rejected WebSocket connection: invalid API key")
    raise PermissionError("Unauthorized")


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """AWS Lambda entry point for the WebSocket custom authorizer."""
    return handleAuthorize(event, context)
