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
   - Audio validation

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

## Audio Flow

The voice chat system follows this flow:

1. **Client Connection**
   - Client connects to WebSocket API with API key
   - Connection ID stored in DynamoDB
   - Uses `$connect` route handled by `connect` Lambda

2. **Audio Transmission**
   - Client captures audio and sends via WebSocket
   - Audio data is base64 encoded
   - Uses 'sendaudio' or 'audio' route
   - Message format:
     ```json
     {
       "action": "audio",
       "data": "base64_encoded_audio",
       "author": "username"
     }
     ```

3. **Processing Pipeline**
   ```
   Client -> WebSocket API -> Process Audio Lambda -> S3 + EventBridge -> Audio Processing Lambda -> Validation Lambda -> Broadcast
   ```

   a. **Initial Reception (Process Audio Lambda)**
      - Receives WebSocket message
      - Validates basic message structure
      - Stores raw audio in S3 with path: `audio/{author}/{timestamp}.pcm`
      - Publishes PENDING event to EventBridge:
        ```json
        {
          "Source": "game-server.audio",
          "DetailType": "SendAudioEvent",
          "Detail": {
            "status": "PENDING",
            "author": "username",
            "s3_key": "audio/path/file.pcm",
            "timestamp": "ISO8601_timestamp"
          }
        }
        ```
      - Broadcasts audio to other connected clients

   b. **Audio Processing (Audio Processing Lambda)**
      - Triggered by EventBridge rule on PENDING status
      - Retrieves audio from S3
      - Applies KMS encryption
      - Updates status to PROCESSING
      - Triggers validation process

   c. **Audio Validation (Validation Lambda)**
      - Triggered by EventBridge rule on PROCESSING status
      - Validates audio format and size:
        - Minimum size: 1KB
        - Maximum size: 5MB
        - Proper base64 encoding
      - Updates status to COMPLETED or FAILED

   d. **Broadcasting**
      - Process Audio Lambda handles broadcasting
      - Uses DynamoDB to get active connections
      - Sends audio to all clients except sender
      - Message format:
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
      - Handles disconnected clients cleanup

4. **Event Flow States**
   ```
   [PENDING] -> [PROCESSING] -> [COMPLETED/FAILED]
   ```
   - PENDING: Initial state when audio is received
   - PROCESSING: Audio is being processed and validated
   - COMPLETED: Audio successfully processed
   - FAILED: Processing or validation failed

5. **Error Handling**
   - Connection errors: Remove stale connections from DynamoDB
   - S3 errors: Return 500 error, log failure
   - Processing errors: Mark event as FAILED
   - Validation errors: Return 400 error with details

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
