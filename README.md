# Game Server Infrastructure

This repository contains the Terraform infrastructure code for a game server with real-time voice chat capabilities.

## Architecture Overview

The infrastructure consists of several key components:

1. **WebSocket API Gateway**
   - Handles real-time communication
   - Supports audio streaming
   - API key authentication
   - Routes: connect, disconnect, sendaudio, audio

2. **Lambda Functions**
   - Connection management (connect/disconnect)
   - Message handling
   - Audio processing
   - Audio validation and broadcasting

3. **Storage**
   - DynamoDB for WebSocket connections
   - S3 bucket for audio storage
   - KMS for audio encryption

4. **Event Processing**
   - EventBridge for event routing
   - CloudWatch for logging and monitoring

5. **Security**
   - Cognito for user authentication
   - API keys for WebSocket access
   - IAM roles and policies
   - KMS encryption for audio data

## Audio Flow

The voice chat system follows this flow:

1. **Client Connection**
   - Client connects to WebSocket API with API key
   - Connection ID stored in DynamoDB
   - Uses `$connect` route handled by `connect` Lambda

2. **Audio Transmission**
   - Client captures audio and sends via WebSocket
   - Audio data is base64 encoded
   - Uses 'sendaudio' route
   - Message format:
     ```json
     {
       "action": "sendaudio",
       "data": "base64_encoded_audio",
       "author": "username"
     }
     ```

3. **Processing Pipeline**
   ```
   Client -> WebSocket API -> Message Lambda -> EventBridge -> Process Audio Lambda -> EventBridge -> Validate Audio Lambda -> Broadcast to Listeners
   ```

   a. **Initial Reception (Message Lambda)**
      - Receives WebSocket message
      - Validates basic message structure
      - Publishes event to EventBridge:
        ```json
        {
          "Source": "voice-chat",
          "DetailType": "SendAudioEvent",
          "Detail": {
            "status": "PENDING",
            "message": {
              "action": "sendaudio",
              "data": "base64_encoded_audio",
              "author": "username"
            },
            "websocket_context": {
              "domain_name": "api-domain",
              "stage": "stage-name",
              "connection_id": "connection-id"
            },
            "timestamp": "ISO8601_timestamp"
          }
        }
        ```

   b. **Audio Processing (Process Audio Lambda)**
      - Triggered by EventBridge rule on PENDING status
      - Stores audio in S3 with path: `audio/{author}/{timestamp}.pcm`
      - Forwards event to validation with S3 reference
      - Event format:
        ```json
        {
          "Source": "voice-chat",
          "DetailType": "SendAudioEvent",
          "Detail": {
            "status": "PENDING",
            "message": {
              "action": "sendaudio",
              "data": "base64_encoded_audio",
              "author": "username"
            },
            "websocket_context": {
              "domain_name": "api-domain",
              "stage": "stage-name",
              "connection_id": "connection-id"
            },
            "s3_key": "audio/{author}/{timestamp}.pcm",
            "timestamp": "ISO8601_timestamp"
          }
        }
        ```

   c. **Audio Validation and Broadcasting (Validate Audio Lambda)**
      - Validates audio format and size
      - Retrieves active connections from DynamoDB
      - Broadcasts validated audio to all listeners except sender
      - Handles stale connection cleanup
      - Broadcast message format:
        ```json
        {
          "action": "audio",
          "data": {
            "audio": "base64_encoded_audio",
            "author": "username",
            "timestamp": "ISO8601_timestamp"
          }
        }
        ```

4. **Error Handling**
   - Connection errors: Remove stale connections from DynamoDB
   - S3 errors: Return 500 error, log failure
   - EventBridge errors: Log and return appropriate status
   - Broadcasting errors: Log and cleanup stale connections
   - Audio validation errors: Return 400 error with reason

5. **Testing Mode**
   - Echo mode available for testing (set via `enable_echo_mode`)
   - When enabled, audio is sent back to sender
   - Useful for testing audio capture and playback

## Detailed Information Flow

### 1. API Gateway (sendaudio route)
**Input:**
```json
{
  "action": "sendaudio",
  "data": "base64_encoded_audio",
  "author": "username"
}
```
**Context:**
```json
{
  "requestContext": {
    "connectionId": "connection-id",
    "domainName": "api-domain",
    "stage": "stage-name"
  }
}
```

### 2. game-server-ws-message Lambda
**Input:** API Gateway WebSocket event
**Processing:**
- Validates message structure
- Extracts WebSocket context
- Constructs EventBridge event

**Output to EventBridge:**
```json
{
  "Source": "voice-chat",
  "DetailType": "SendAudioEvent",
  "Detail": {
    "status": "PENDING",
    "message": {
      "action": "sendaudio",
      "data": "base64_encoded_audio",
      "author": "username"
    },
    "websocket_context": {
      "domain_name": "api-domain",
      "stage": "stage-name",
      "connection_id": "connection-id"
    },
    "timestamp": "ISO8601_timestamp"
  },
  "EventBusName": "game-server-events"
}
```

### 3. game-server-audio-audio-processing-rule (EventBridge Rule)
**Pattern Match:**
```json
{
  "source": ["voice-chat"],
  "detail-type": ["SendAudioEvent"],
  "detail": {
    "status": ["PENDING"],
    "websocket_context": {
      "domain_name": [{ "exists": true }],
      "stage": [{ "exists": true }],
      "connection_id": [{ "exists": true }]
    },
    "message": {
      "data": [{ "exists": true }]
    }
  }
}
```

### 4. game-server-audio-process-audio Lambda
**Input from EventBridge Rule:**
```json
{
  "version": "0",
  "id": "event-id",
  "detail-type": "SendAudioEvent",
  "source": "voice-chat",
  "account": "aws-account-id",
  "time": "timestamp",
  "region": "aws-region",
  "detail": {
    "status": "PENDING",
    "message": {
      "action": "sendaudio",
      "data": "base64_encoded_audio",
      "author": "username"
    },
    "websocket_context": {
      "domain_name": "api-domain",
      "stage": "stage-name",
      "connection_id": "connection-id"
    },
    "timestamp": "ISO8601_timestamp"
  }
}
```

**Environment Variables Used:**
- AUDIO_BUCKET: S3 bucket for audio storage
- EVENT_BUS_ARN: EventBridge bus ARN
- KMS_KEY_ID: KMS key for audio encryption

**Processing Steps:**
1. Extract audio data and context from event
2. Store in S3:
   ```python
   s3.put_object(
       Bucket=os.environ['AUDIO_BUCKET'],
       Key=f"audio/{author}/{timestamp}.pcm",
       Body=base64.b64decode(audio_data)
   )
   ```

**Outputs:**

1. **S3 Storage Output:**
   - Location: `s3://{AUDIO_BUCKET}/audio/{author}/{timestamp}.pcm`
   - Content: Raw PCM audio data (base64 decoded)
   - Metadata:
     ```json
     {
       "author": "username",
       "timestamp": "ISO8601_timestamp",
       "content-type": "audio/pcm"
     }
     ```

2. **EventBridge Output (To Validation Rule):**
   ```json
   {
     "Source": "voice-chat",
     "DetailType": "SendAudioEvent",
     "Detail": {
       "status": "PENDING",
       "message": {
         "action": "sendaudio",
         "data": "base64_encoded_audio",
         "author": "username"
       },
       "websocket_context": {
         "domain_name": "api-domain",
         "stage": "stage-name",
         "connection_id": "connection-id"
       },
       "s3_key": "audio/{author}/{timestamp}.pcm",
       "timestamp": "ISO8601_timestamp"
     },
     "EventBusName": "game-server-events"
   }
   ```

3. **Return Value (Lambda Response):**
   ```json
   {
     "statusCode": 200,
     "body": {
       "message": "Audio stored and sent for validation",
       "s3_key": "audio/{author}/{timestamp}.pcm"
     }
   }
   ```

4. **Error Responses:**
   - S3 Storage Error:
     ```json
     {
       "statusCode": 500,
       "body": "Error storing audio"
     }
     ```

**Side Effects:**
1. CloudWatch Logs:
   - Audio storage success/failure
   - Event publishing status
2. CloudWatch Metrics:
   - Audio processing latency
   - Storage operation timing

### 5. game-server-audio-audio-validation-rule (EventBridge Rule)
**Pattern Match:**
```json
{
  "source": ["voice-chat"],
  "detail-type": ["SendAudioEvent"],
  "detail": {
    "status": ["PENDING"],
    "websocket_context": {
      "domain_name": [{ "exists": true }],
      "stage": [{ "exists": true }],
      "connection_id": [{ "exists": true }]
    },
    "message": {
      "data": [{ "exists": true }],
      "author": [{ "exists": true }]
    },
    "s3_key": [{ "exists": true }]
  }
}
```

### 6. game-server-audio-validate-audio Lambda
**Input:** EventBridge event from validation rule
**Environment Variables Used:**
- CONNECTIONS_TABLE: DynamoDB table for active connections
- AUDIO_BUCKET: S3 bucket for audio storage

**Processing Steps:**
1. Validate audio format and size
2. Get active connections from DynamoDB
3. Broadcast validated audio to all listeners

**Outputs:**

1. **Broadcast to Listeners (On Success):**
   ```json
   {
     "action": "audio",
     "data": {
       "audio": "base64_encoded_audio",
       "author": "username",
       "timestamp": "ISO8601_timestamp",
       "status": "VALIDATED"
     }
   }
   ```

2. **Broadcast to Listeners (On Failure):**
   ```json
   {
     "action": "audio_status",
     "data": {
       "status": "FAILED",
       "author": "username",
       "timestamp": "ISO8601_timestamp",
       "message": "Validation failure reason"
     }
   }
   ```

**Side Effects:**
1. Stale Connection Cleanup:
   - Removes invalid connections from DynamoDB when broadcast fails
2. CloudWatch Logs:
   - Validation results
   - Broadcasting statistics
   - Connection cleanup events
3. CloudWatch Metrics:
   - Validation latency
   - Broadcast success rate
   - Connection management stats

### Data Flow Summary
```
[Client] 
   ↓ sendaudio (WebSocket)
[API Gateway] 
   ↓ WebSocket event
[message Lambda] 
   ↓ EventBridge event (PENDING)
[processing rule] 
   ↓ Matched event
[process-audio Lambda] 
   ↓ Store in S3
   ↓ EventBridge event with S3 key
[validation rule]
   ↓ Matched event
[validate-audio Lambda]
   ↓ Validate audio
   ↓ Broadcast to listeners if valid
[Listeners]
```

## Infrastructure Components

### WebSocket Module
- API Gateway v2 (WebSocket)
- API key authentication
- Stage configuration
- CloudWatch logging

### Audio Processing Module
- Lambda functions for processing
- S3 bucket for storage
- KMS encryption
- EventBridge rules and targets

### Event Processing
- Custom EventBridge bus
- Event rules for audio processing
- CloudWatch logging
- Error handling

## Environment Variables

Key environment variables used in the Lambda functions:
- CONNECTIONS_TABLE: DynamoDB table name
- AUDIO_BUCKET: S3 bucket name
- EVENT_BUS_NAME: EventBridge bus name
- EVENT_SOURCE: Event source identifier
- EVENT_DETAIL_TYPE: Event detail type

### Message Lambda
- CONNECTIONS_TABLE: DynamoDB table for connections
- EVENT_SOURCE: Source name for EventBridge events
- EVENT_BUS_NAME: Name of the EventBridge bus

### Process Audio Lambda
- AUDIO_BUCKET: S3 bucket for audio storage
- KMS_KEY_ID: KMS key for audio encryption
- EVENT_BUS_ARN: EventBridge bus ARN
- CONNECTIONS_TABLE: DynamoDB table for connections

### Validate Audio Lambda
- CONNECTIONS_TABLE: DynamoDB table for connections
- ECHO_MODE: Enable/disable echo testing mode

## Security

1. **Authentication**
   - Cognito user pools
   - API key required for WebSocket
   - IAM roles per service

2. **Encryption**
   - KMS for audio data
   - HTTPS for all API communication
   - Secure parameter storage in SSM

## Monitoring

- CloudWatch logs for all components
- EventBridge for event tracking
- API Gateway metrics
- Lambda function metrics

## Deployment

1. Prerequisites:
   - AWS CLI configured
   - Terraform installed
   - Required permissions

2. Deployment Steps:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. Post-deployment:
   - Get WebSocket URL from outputs
   - Configure client with API key
   - Test connections

## Outputs

Important infrastructure outputs:
- WebSocket endpoint URL
- API key (sensitive)
- S3 bucket name
- EventBridge bus name
- CloudWatch log groups

## Troubleshooting

Common issues and solutions:
1. Connection Issues
   - Check API key in headers
   - Verify WebSocket URL
   - Check CloudWatch logs

2. Audio Issues
   - Verify audio format
   - Check S3 bucket permissions
   - Monitor EventBridge events

3. Processing Issues
   - Check Lambda logs
   - Verify EventBridge rules
   - Check IAM permissions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Pending Tasks

### Audio Flow Verification
1. **Process Audio to Listener Flow**
   - [x] Verify audio storage in S3
   - [x] Verify EventBridge event handling
   - [x] Test broadcasting to multiple listeners
   - [x] Validate WebSocket context preservation
   - [ ] Verify client message reception
   - [ ] Test client audio playback
   - [ ] Verify audio format and quality in client
   - [ ] Monitor end-to-end latency

2. **Testing Scenarios**
   - [x] Single sender audio transmission
   - [ ] Multiple concurrent senders
   - [ ] Client reconnection handling
   - [ ] Network interruption recovery
   - [ ] Large audio payload handling
   - [ ] Error condition recovery

3. **Monitoring Points**
   - [x] CloudWatch Logs for process-audio Lambda
   - [x] EventBridge event delivery success
   - [x] S3 object creation verification
   - [x] WebSocket API Gateway message delivery
   - [ ] Client message reception confirmation
   - [ ] Client-side error logging
   - [ ] End-to-end latency metrics

4. **Success Criteria**
   - [x] Audio successfully stored in S3
   - [x] Events properly processed through EventBridge
   - [x] API Gateway successfully sends messages
   - [ ] All listeners receive and play audio
   - [ ] No duplicate audio playback
   - [ ] Proper client-side error handling
   - [ ] Clean connection management in client
   - [ ] Consistent audio quality in playback
   - [ ] Resource cleanup on client disconnection
