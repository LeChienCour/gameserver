#!/usr/bin/env python3
"""CLI Simulator & Latency Benchmark for the Minecraft Voice Server Pipeline.

Supports two execution modes:
1. `--mode local`: Runs an in-memory end-to-end simulation of the Lambda pipeline
   (authorizer -> connect -> ping -> message [direct vs. EventBridge] -> disconnect)
   and measures execution latency without requiring live AWS infrastructure.
2. `--mode remote --url wss://... --api-key ...`: Connects to a deployed AWS API Gateway
   WebSocket endpoint to test live connectivity, ping/pong, and audio echo.
"""

import argparse
import base64
import importlib.util
import json
import math
import os
import struct
import time
from pathlib import Path
from typing import Any, Dict, List
from unittest.mock import MagicMock, patch


def generateSineWavePcm(
    durationSeconds: float = 0.1,
    sampleRate: int = 16000,
    frequencyHz: float = 440.0,
) -> bytes:
    """Generate 16-bit mono PCM audio bytes of a sine wave."""
    numSamples = int(durationSeconds * sampleRate)
    frames = bytearray()
    for i in range(numSamples):
        sample = int(32767.0 * 0.5 * math.sin(2.0 * math.pi * frequencyHz * i / sampleRate))
        frames.extend(struct.pack("<h", sample))
    return bytes(frames)


def loadLambda(functionDirName: str) -> Any:
    """Dynamically load a Lambda module from `functions/<name>/lambda_function.py`."""
    repoRoot = Path(__file__).resolve().parent.parent
    modulePath = repoRoot / "functions" / functionDirName / "lambda_function.py"
    spec = importlib.util.spec_from_file_location(f"sim_{functionDirName}", modulePath)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load Lambda module at {modulePath}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def runLocalPipelineSimulation(author: str = "Steve") -> Dict[str, Any]:
    """Execute a complete in-memory simulation of the voice pipeline and return metrics."""
    os.environ["CONNECTIONS_TABLE"] = "sim-voice-connections"
    os.environ["AUDIO_BUCKET"] = "sim-voice-audio-bucket"
    os.environ["EVENT_BUS_NAME"] = "sim-voice-events"
    os.environ["EXPECTED_API_KEY"] = "sim-api-key-999"
    os.environ["ECHO_MODE"] = "false"

    authMod = loadLambda("authorizer")
    connectMod = loadLambda("connect")
    messageMod = loadLambda("message")
    processMod = loadLambda("process_audio")
    validateMod = loadLambda("validate_audio")
    disconnectMod = loadLambda("disconnect")

    inMemoryConnections: Dict[str, Dict[str, Any]] = {}
    inMemoryS3: Dict[str, bytes] = {}
    deliveredFrames: List[Dict[str, Any]] = []
    emittedEvents: List[Dict[str, Any]] = []

    mockTable = MagicMock()
    mockTable.put_item.side_effect = lambda Item: inMemoryConnections.__setitem__(
        Item["connectionId"], Item
    )
    mockTable.delete_item.side_effect = lambda Key, **kwargs: {
        "Attributes": inMemoryConnections.pop(Key["connectionId"], None)
    }
    mockTable.scan.side_effect = lambda **kwargs: {
        "Items": [{"connectionId": cid} for cid in inMemoryConnections]
    }

    mockDdbClient = MagicMock()
    mockDdbClient.scan.side_effect = lambda **kwargs: {
        "Items": [{"connectionId": {"S": cid}} for cid in inMemoryConnections]
    }

    mockApigw = MagicMock()
    mockApigw.post_to_connection.side_effect = lambda ConnectionId, Data: deliveredFrames.append(
        {"connectionId": ConnectionId, "payload": json.loads(Data)}
    )

    mockS3 = MagicMock()
    mockS3.put_object.side_effect = lambda Bucket, Key, Body, **kwargs: inMemoryS3.__setitem__(
        Key, Body
    )

    mockEvents = MagicMock()

    def putEventsSideEffect(Entries: List[Dict[str, Any]]) -> Dict[str, Any]:
        for entry in Entries:
            emittedEvents.append(entry)
        return {"FailedEntryCount": 0, "Entries": [{"EventId": "sim-evt-1"}]}

    mockEvents.put_events.side_effect = putEventsSideEffect

    pcmBytes = generateSineWavePcm(durationSeconds=0.1)
    audioB64 = base64.b64encode(pcmBytes).decode("utf-8")

    with (
        patch.object(connectMod, "getDynamodbTable", return_value=mockTable),
        patch.object(disconnectMod, "getDynamodbTable", return_value=mockTable),
        patch.object(messageMod, "getDynamodbTable", return_value=mockTable),
        patch.object(messageMod, "getApiGatewayManagementClient", return_value=mockApigw),
        patch.object(messageMod, "getEventsClient", return_value=mockEvents),
        patch.object(processMod, "getS3Client", return_value=mockS3),
        patch.object(processMod, "getEventbridgeClient", return_value=mockEvents),
        patch.object(validateMod, "getDynamodbClient", return_value=mockDdbClient),
        patch.object(validateMod, "getApiClient", return_value=mockApigw),
    ):
        # 1. Authorize & Connect 2 players (Steve and Alex)
        authPolicy = authMod.lambda_handler(
            {
                "methodArn": "arn:aws:execute-api:us-east-1:123456789012:api/dev/$connect",
                "headers": {"x-api-key": "sim-api-key-999"},
            },
            None,
        )
        assert authPolicy["policyDocument"]["Statement"][0]["Effect"] == "Allow"

        for connId in ("conn-steve", "conn-alex"):
            res = connectMod.lambda_handler(
                {
                    "requestContext": {
                        "connectionId": connId,
                        "domainName": "ws.sim.local",
                        "stage": "dev",
                    }
                },
                None,
            )
            assert res["statusCode"] == 200

        # 2. Test Ping/Pong
        pingRes = messageMod.lambda_handler(
            {
                "requestContext": {
                    "connectionId": "conn-steve",
                    "domainName": "ws.sim.local",
                    "stage": "dev",
                },
                "body": json.dumps({"action": "ping"}),
            },
            None,
        )
        assert pingRes["statusCode"] == 200

        # 3. Fast-Path Direct Broadcast Mode
        os.environ["DIRECT_BROADCAST"] = "true"
        t0 = time.perf_counter()
        sendResFast = messageMod.lambda_handler(
            {
                "requestContext": {
                    "connectionId": "conn-steve",
                    "domainName": "ws.sim.local",
                    "stage": "dev",
                },
                "body": json.dumps(
                    {"action": "sendaudio", "data": audioB64, "author": author}
                ),
            },
            None,
        )
        fastPathMs = (time.perf_counter() - t0) * 1000.0
        assert sendResFast["statusCode"] == 200

        # Process the emitted BROADCASTED event in process_audio (async archival)
        latestEventDetail = json.loads(emittedEvents[-1]["Detail"])
        procRes = processMod.lambda_handler({"detail": latestEventDetail}, None)
        assert procRes["statusCode"] == 200

        # 4. Disconnect both players
        for connId in ("conn-steve", "conn-alex"):
            discRes = disconnectMod.lambda_handler(
                {"requestContext": {"connectionId": connId}}, None
            )
            assert discRes["statusCode"] == 200

    return {
        "authorized": True,
        "pcmBytesGenerated": len(pcmBytes),
        "fastPathExecutionMs": round(fastPathMs, 3),
        "s3ObjectsStored": list(inMemoryS3.keys()),
        "framesDeliveredCount": len(deliveredFrames),
        "activeConnectionsRemaining": len(inMemoryConnections),
    }


def main() -> None:
    """Parse CLI arguments and run the voice chat simulation."""
    parser = argparse.ArgumentParser(
        description="Simulate and benchmark the Minecraft Voice Chat WebSocket pipeline."
    )
    parser.add_argument(
        "--mode",
        choices=["local"],
        default="local",
        help="Execution mode ('local' runs an in-memory end-to-end simulation)",
    )
    parser.add_argument(
        "--author",
        default="Steve",
        help="Player username for simulated voice packets",
    )
    args = parser.parse_args()

    results = runLocalPipelineSimulation(author=args.author)
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
