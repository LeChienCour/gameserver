"""Unit tests for all 5 AWS Lambda functions in the Minecraft Voice Server.

Compatible with both `pytest` and standard library `python3 -m unittest`.
"""

import base64
import importlib.util
import json
import os
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch


def loadLambdaModule(functionDirName: str) -> Any:
    """Dynamically load a Lambda function module by directory name."""
    repoRoot = Path(__file__).resolve().parent.parent
    modulePath = repoRoot / "functions" / functionDirName / "lambda_function.py"
    spec = importlib.util.spec_from_file_location(
        f"lambda_{functionDirName}", modulePath
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestConnectLambda(unittest.TestCase):
    """Tests for functions/connect/lambda_function.py."""

    @patch.dict(os.environ, {"CONNECTIONS_TABLE": "test-connections"})
    def testConnectSuccess(self) -> None:
        """Verify $connect stores a single item with TTL and does not call get_item."""
        connectMod = loadLambdaModule("connect")

        mockTable = MagicMock()
        with patch.object(connectMod, "getDynamodbTable", return_value=mockTable):
            event = {
                "requestContext": {
                    "connectionId": "conn-123",
                    "domainName": "ws.example.com",
                    "stage": "dev",
                }
            }
            response = connectMod.lambda_handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(response["body"], "Connected.")
        mockTable.put_item.assert_called_once()
        storedItem = mockTable.put_item.call_args.kwargs["Item"]
        self.assertEqual(storedItem["connectionId"], "conn-123")
        self.assertEqual(storedItem["domain"], "ws.example.com")
        self.assertEqual(storedItem["stage"], "dev")
        self.assertIsInstance(storedItem["ttl"], int)
        mockTable.get_item.assert_not_called()

    @patch.dict(os.environ, {"CONNECTIONS_TABLE": "test-connections"})
    def testConnectMissingConnectionId(self) -> None:
        """Verify $connect returns 400 when connectionId is missing."""
        connectMod = loadLambdaModule("connect")
        response = connectMod.lambda_handler({"requestContext": {}}, None)
        self.assertEqual(response["statusCode"], 400)


class TestDisconnectLambda(unittest.TestCase):
    """Tests for functions/disconnect/lambda_function.py."""

    @patch.dict(os.environ, {"CONNECTIONS_TABLE": "test-connections"})
    def testDisconnectSuccess(self) -> None:
        """Verify $disconnect performs a single delete_item without redundant get_item calls."""
        disconnectMod = loadLambdaModule("disconnect")

        mockTable = MagicMock()
        mockTable.delete_item.return_value = {
            "Attributes": {"connectionId": "conn-123"}
        }
        with patch.object(disconnectMod, "getDynamodbTable", return_value=mockTable):
            event = {"requestContext": {"connectionId": "conn-123"}}
            response = disconnectMod.lambda_handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(response["body"], "Disconnected.")
        mockTable.delete_item.assert_called_once_with(
            Key={"connectionId": "conn-123"},
            ReturnValues="ALL_OLD",
        )
        mockTable.get_item.assert_not_called()


class TestMessageLambda(unittest.TestCase):
    """Tests for functions/message/lambda_function.py."""

    @patch.dict(os.environ, {"CONNECTIONS_TABLE": "test-connections"})
    def testPingActionSendsPong(self) -> None:
        """Verify ping route sends pong frame via API Gateway Management API."""
        messageMod = loadLambdaModule("message")

        mockTable = MagicMock()
        mockApigw = MagicMock()
        with (
            patch.object(messageMod, "getDynamodbTable", return_value=mockTable),
            patch.object(
                messageMod, "getApiGatewayManagementClient", return_value=mockApigw
            ),
        ):
            event = {
                "requestContext": {
                    "connectionId": "conn-1",
                    "domainName": "ws.example.com",
                    "stage": "dev",
                },
                "body": json.dumps({"action": "ping"}),
            }
            response = messageMod.lambda_handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        mockApigw.post_to_connection.assert_called_once()
        mockTable.scan.assert_not_called()

    @patch.dict(
        os.environ,
        {
            "CONNECTIONS_TABLE": "test-connections",
            "EVENT_BUS_NAME": "test-bus",
            "DIRECT_BROADCAST": "false",
        },
    )
    def testSendAudioEventBridgeModeNoScan(self) -> None:
        """Verify sendaudio in standard mode does NOT scan DynamoDB and checks FailedEntryCount."""
        messageMod = loadLambdaModule("message")

        mockTable = MagicMock()
        mockApigw = MagicMock()
        mockEvents = MagicMock()
        mockEvents.put_events.return_value = {"FailedEntryCount": 0, "Entries": [{}]}

        with (
            patch.object(messageMod, "getDynamodbTable", return_value=mockTable),
            patch.object(
                messageMod, "getApiGatewayManagementClient", return_value=mockApigw
            ),
            patch.object(messageMod, "getEventsClient", return_value=mockEvents),
        ):
            validAudio = base64.b64encode(b"\x00\x01" * 1024).decode("utf-8")
            event = {
                "requestContext": {
                    "connectionId": "conn-sender",
                    "domainName": "ws.example.com",
                    "stage": "dev",
                },
                "body": json.dumps(
                    {
                        "action": "sendaudio",
                        "data": validAudio,
                        "author": "Steve",
                    }
                ),
            }

            response = messageMod.lambda_handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        mockTable.scan.assert_not_called()
        mockEvents.put_events.assert_called_once()

    @patch.dict(
        os.environ,
        {
            "CONNECTIONS_TABLE": "test-connections",
            "EVENT_BUS_NAME": "test-bus",
            "DIRECT_BROADCAST": "true",
            "ECHO_MODE": "false",
        },
    )
    def testSendAudioDirectBroadcastFastPath(self) -> None:
        """Verify DIRECT_BROADCAST=true broadcasts immediately and sets status=BROADCASTED."""
        messageMod = loadLambdaModule("message")

        mockTable = MagicMock()
        mockTable.scan.return_value = {
            "Items": [
                {"connectionId": "conn-sender"},
                {"connectionId": "conn-listener"},
            ]
        }
        mockApigw = MagicMock()
        mockEvents = MagicMock()
        mockEvents.put_events.return_value = {"FailedEntryCount": 0, "Entries": [{}]}

        with (
            patch.object(messageMod, "getDynamodbTable", return_value=mockTable),
            patch.object(
                messageMod, "getApiGatewayManagementClient", return_value=mockApigw
            ),
            patch.object(messageMod, "getEventsClient", return_value=mockEvents),
        ):
            validAudio = base64.b64encode(b"\x00\x01" * 1024).decode("utf-8")
            event = {
                "requestContext": {
                    "connectionId": "conn-sender",
                    "domainName": "ws.example.com",
                    "stage": "dev",
                },
                "body": json.dumps(
                    {
                        "action": "sendaudio",
                        "data": validAudio,
                        "author": "Steve",
                    }
                ),
            }

            response = messageMod.lambda_handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        bodyData = json.loads(response["body"])
        self.assertEqual(bodyData["broadcast"]["sent"], 1)
        mockApigw.post_to_connection.assert_called_once()
        self.assertEqual(
            mockApigw.post_to_connection.call_args.kwargs["ConnectionId"],
            "conn-listener",
        )

        publishedEntry = mockEvents.put_events.call_args.kwargs["Entries"][0]
        detail = json.loads(publishedEntry["Detail"])
        self.assertEqual(detail["status"], "BROADCASTED")


class TestProcessAudioLambda(unittest.TestCase):
    """Tests for functions/process_audio/lambda_function.py."""

    def testBuildS3KeyCollisionFreeAndSanitized(self) -> None:
        """Verify two consecutive S3 keys in the same second are unique and sanitized."""
        processMod = loadLambdaModule("process_audio")
        key1 = processMod.buildS3Key("../malicious/user!")
        key2 = processMod.buildS3Key("../malicious/user!")

        self.assertNotEqual(key1, key2)
        self.assertNotIn("..", key1)
        self.assertTrue(key1.startswith("audio/___malicious_user_/"))
        self.assertTrue(key1.endswith(".pcm"))

    @patch.dict(os.environ, {"AUDIO_BUCKET": "test-audio-bucket"})
    def testProcessAudioSkipsValidationEventWhenBroadcasted(self) -> None:
        """Verify process_audio stores in S3 but skips second EventBridge hop if status=BROADCASTED."""
        processMod = loadLambdaModule("process_audio")

        mockS3 = MagicMock()
        mockEvents = MagicMock()
        with (
            patch.object(processMod, "getS3Client", return_value=mockS3),
            patch.object(processMod, "getEventbridgeClient", return_value=mockEvents),
        ):
            validAudio = base64.b64encode(b"\x00\x01" * 1024).decode("utf-8")
            event = {
                "detail": {
                    "status": "BROADCASTED",
                    "message": {
                        "action": "sendaudio",
                        "data": validAudio,
                        "author": "Alex",
                    },
                    "websocket_context": {
                        "domain_name": "ws.example.com",
                        "stage": "dev",
                        "connection_id": "conn-1",
                    },
                }
            }

            response = processMod.lambda_handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        mockS3.put_object.assert_called_once()
        mockEvents.put_events.assert_not_called()


class TestValidateAudioLambda(unittest.TestCase):
    """Tests for functions/validate_audio/lambda_function.py."""

    @patch.dict(
        os.environ,
        {
            "CONNECTIONS_TABLE": "test-connections",
            "ECHO_MODE": "false",
        },
    )
    def testValidateAudioBroadcastAndPagination(self) -> None:
        """Verify paginated DynamoDB scan and stale GoneException cleanup."""
        validateMod = loadLambdaModule("validate_audio")

        mockDdb = MagicMock()
        mockDdb.scan.side_effect = [
            {
                "Items": [{"connectionId": {"S": "conn-sender"}}],
                "LastEvaluatedKey": {"connectionId": {"S": "conn-sender"}},
            },
            {
                "Items": [
                    {"connectionId": {"S": "conn-ok"}},
                    {"connectionId": {"S": "conn-stale"}},
                ]
            },
        ]

        mockApigw = MagicMock()

        def sideEffectPost(Data: str, ConnectionId: str) -> None:
            if ConnectionId == "conn-stale":
                raise Exception(
                    "An error occurred (GoneException) when calling PostToConnection"
                )

        mockApigw.post_to_connection.side_effect = sideEffectPost

        with (
            patch.object(validateMod, "getDynamodbClient", return_value=mockDdb),
            patch.object(validateMod, "getApiClient", return_value=mockApigw),
        ):
            validAudio = base64.b64encode(b"\x00\x01" * 1024).decode("utf-8")
            event = {
                "detail": {
                    "status": "PROCESSED",
                    "s3_key": "audio/Steve/123.pcm",
                    "message": {
                        "data": validAudio,
                        "author": "Steve",
                    },
                    "websocket_context": {
                        "connection_id": "conn-sender",
                        "domain_name": "ws.example.com",
                        "stage": "dev",
                    },
                }
            }

            response = validateMod.lambda_handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        stats = json.loads(response["body"])["statistics"]
        self.assertEqual(stats["total_connections"], 3)
        self.assertEqual(stats["successful"], 1)
        self.assertEqual(stats["deleted"], 1)
        mockDdb.delete_item.assert_called_once_with(
            TableName="test-connections",
            Key={"connectionId": {"S": "conn-stale"}},
        )


if __name__ == "__main__":
    unittest.main()
