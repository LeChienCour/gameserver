# Game Server Infrastructure (Demo Project)

> **⚠️ DEMO PROJECT DISCLAIMER**  
> This repository contains a demonstration implementation of a game server infrastructure with real-time voice chat capabilities. 
> It is intended for educational and demonstration purposes only and should not be used in production without proper security review and modifications.
> The infrastructure code and documentation serve as an example of modern DevOps practices, CI/CD implementation, and AWS infrastructure management.

This repository demonstrates the Terraform infrastructure code for a game server with real-time voice chat capabilities. 
The project showcases various AWS services integration, infrastructure as code practices, and modern CI/CD implementation.
test
## Architecture Overview

The infrastructure consists of several key components:

1. **WebSocket API Gateway**
   - Handles real-time communication
   - Supports audio streaming
   - API key authentication
   - Routes:
     - `$connect`: Handles new WebSocket connections
     - `$disconnect`: Handles connection termination
     - `sendaudio`: Processes incoming audio data
     - `$default`: Handles unmatched routes

2. **Lambda Functions**
   - `connect`: Manages new WebSocket connections and stores connection data
   - `disconnect`: Cleans up terminated connections
   - `message`: Handles WebSocket messages and audio events
   - `process_audio`: Processes and stores audio in S3
   - `validate_audio`: Validates and broadcasts audio to connected clients

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

## Connection Flow

1. **Initial Connection (`$connect` route)**
   - Client connects to WebSocket API with API key
   - `connect` Lambda function:
     - Generates unique connection ID
     - Stores connection details in DynamoDB:
       ```json
       {
         "connectionId": "unique-id",
         "connectedAt": "ISO8601_timestamp",
         "domain": "api-domain",
         "stage": "stage-name"
       }
       ```
     - Returns 200 status on success

2. **Disconnection (`$disconnect` route)**
   - Triggered when client disconnects
   - `disconnect` Lambda function:
     - Removes connection record from DynamoDB
     - Cleans up any associated resources
     - Returns 200 status on success

## Audio Flow

1. **Audio Transmission**
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

2. **Processing Pipeline**
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

## Error Handling

1. **Connection Errors**
   - Invalid API key: 403 Forbidden
   - Connection failure: 500 Internal Server Error
   - Stale connections: Automatically removed from DynamoDB

2. **Audio Processing Errors**
   - Invalid audio format: 400 Bad Request
   - Processing failure: 500 Internal Server Error
   - Storage failure: 500 Internal Server Error

3. **Broadcasting Errors**
   - Stale connections: Removed during broadcast attempts
   - Broadcast failure: Logged and continues to next recipient

## Testing Mode

- Echo mode available (set via `enable_echo_mode`)
- When enabled, audio is sent back to sender
- Useful for testing audio capture and playback

## Environment Variables

1. **Lambda Functions**
   - `CONNECTIONS_TABLE`: DynamoDB table for WebSocket connections
   - `AUDIO_BUCKET`: S3 bucket for audio storage
   - `EVENT_BUS_NAME`: EventBridge bus name
   - `EVENT_SOURCE`: Source name for events
   - `KMS_KEY_ID`: KMS key for encryption
   - `ECHO_MODE`: Enable/disable echo testing mode

2. **API Gateway**
   - Stage variables and settings defined in Terraform
   - Logging and monitoring configurations

## Infrastructure Management

1. **Deployment**
   - Uses Terraform for infrastructure as code
   - Modular design with separate concerns
   - Automated resource creation and configuration

2. **Monitoring**
   - CloudWatch logs for all components
   - Metrics and alarms for critical paths
   - Error tracking and reporting

3. **Security**
   - IAM roles with least privilege
   - Encryption in transit and at rest
   - API key management
   - User authentication via Cognito

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
   - [x] Verify client message reception
   - [ ] Test client audio playback
   - [ ] Verify audio format and quality in client
   - [x] Monitor end-to-end latency

2. **Testing Scenarios**
   - [x] Single sender audio transmission
   - [x] Multiple concurrent senders
   - [x] Client reconnection handling
   - [x] Network interruption recovery
   - [ ] Large audio payload handling
   - [x] Error condition recovery

3. **Monitoring Points**
   - [x] CloudWatch Logs for process-audio Lambda
   - [x] EventBridge event delivery success
   - [x] S3 object creation verification
   - [x] WebSocket API Gateway message delivery
   - [x] Client message reception confirmation
   - [x] Client-side error logging
   - [x] End-to-end latency metrics

4. **Success Criteria**
   - [x] Audio successfully stored in S3
   - [x] Events properly processed through EventBridge
   - [x] API Gateway successfully sends messages
   - [x] All listeners receive and play audio
   - [x] No duplicate audio playback
   - [x] Proper client-side error handling
   - [x] Clean connection management in client
   - [ ] Consistent audio quality in playback
   - [x] Resource cleanup on client disconnection

### Deployment Infrastructure
1. **CI/CD Pipeline**
   - [x] Set up GitHub Actions workflows
   - [x] Configure AWS credentials and permissions
   - [x] Implement PR environment creation
   - [x] Add production deployment process
   - [x] Configure Terraform backend
   - [ ] Add deployment notifications
   - [ ] Implement rollback mechanism

2. **Infrastructure Management**
   - [x] Create Terraform state bucket
   - [x] Set up DynamoDB locking table
   - [x] Configure IAM roles and policies
   - [x] Implement SSM-based deployment
   - [ ] Add backup automation
   - [ ] Implement disaster recovery plan
   - [ ] Set up infrastructure monitoring

3. **Security Implementation**
   - [x] Configure SSM access
   - [x] Set up least privilege IAM roles
   - [x] Implement secure secret management
   - [ ] Add WAF protection
   - [ ] Implement network security groups
   - [ ] Set up security monitoring
   - [ ] Configure audit logging

4. **Monitoring and Logging**
   - [x] Set up CloudWatch logging
   - [x] Configure SSM session logging
   - [ ] Add performance metrics
   - [ ] Set up alerting
   - [ ] Implement log aggregation
   - [ ] Create monitoring dashboards
   - [ ] Configure cost monitoring

5. **Documentation**
   - [x] Document deployment process
   - [x] Add infrastructure requirements
   - [x] Include security best practices
   - [ ] Create troubleshooting guide
   - [ ] Add architecture diagrams
   - [ ] Document backup procedures
   - [ ] Create runbooks

6. **Testing**
   - [x] Implement PR environment testing
   - [x] Add deployment verification
   - [ ] Create load tests
   - [ ] Add security scanning
   - [ ] Implement integration tests
   - [ ] Add performance testing
   - [ ] Create chaos testing scenarios

7. **Optimization**
   - [ ] Optimize deployment speed
   - [ ] Improve resource utilization
   - [ ] Enhance error handling
   - [ ] Optimize cost management
   - [ ] Improve scalability
   - [ ] Enhance backup efficiency
   - [ ] Optimize log management

## Deployment Requirements

### AWS Resources Required

1. **S3 Bucket for Terraform State**
   ```hcl
   resource "aws_s3_bucket" "terraform_state" {
     bucket = "your-terraform-state-bucket"
     versioning {
       enabled = true
     }
     server_side_encryption_configuration {
       rule {
         apply_server_side_encryption_by_default {
           sse_algorithm = "AES256"
         }
       }
     }
   }
   ```

2. **DynamoDB Table for State Locking**
   ```hcl
   resource "aws_dynamodb_table" "terraform_locks" {
     name         = "your-terraform-locks-table"
     billing_mode = "PAY_PER_REQUEST"
     hash_key     = "LockID"
     attribute {
       name = "LockID"
       type = "S"
     }
   }
   ```

3. **IAM Role for Deployment**
   ```hcl
   resource "aws_iam_role" "deployment_role" {
     name = "game-server-deployment-role"
     
     assume_role_policy = jsonencode({
       Version = "2012-10-17"
       Statement = [
         {
           Action = "sts:AssumeRole"
           Effect = "Allow"
           Principal = {
             Service = "ec2.amazonaws.com"
           }
         }
       ]
     })
   }

   resource "aws_iam_role_policy" "deployment_policy" {
     name = "game-server-deployment-policy"
     role = aws_iam_role.deployment_role.id

     policy = jsonencode({
       Version = "2012-10-17"
       Statement = [
         {
           Effect = "Allow"
           Action = [
             "ec2:*",
             "s3:*",
             "ssm:*",
             "iam:PassRole",
             "cloudwatch:PutMetricData",
             "logs:CreateLogGroup",
             "logs:CreateLogStream",
             "logs:PutLogEvents"
           ]
           Resource = "*"
         }
       ]
     })
   }
   ```

### Required GitHub Secrets

1. AWS Credentials:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. Terraform Backend:
   - `TF_STATE_BUCKET`: S3 bucket name for Terraform state
   - `TF_LOCK_TABLE`: DynamoDB table name for state locking

### Deployment Process

1. **Pull Request Workflow**
   - Triggered on PR creation/update
   - Creates temporary test environment
   - Deploys infrastructure and mod
   - Runs tests
   - Cleans up resources automatically

2. **Production Deployment**
   - Triggered on merge to main
   - Deploys to production environment
   - Uses production state file
   - Creates GitHub deployment status
   - Monitors deployment health

### Deployment Commands

1. **Local Testing**
   ```bash
   # Initialize Terraform
   terraform init -backend-config="bucket=your-tf-state-bucket" \
                 -backend-config="key=dev/terraform.tfstate" \
                 -backend-config="region=us-east-1" \
                 -backend-config="dynamodb_table=your-tf-locks-table"

   # Plan changes
   terraform plan -out=tfplan

   # Apply changes
   terraform apply tfplan
   ```

2. **Manual Deployment**
   ```bash
   # Trigger workflow manually
   gh workflow run deploy-game-server.yaml
   ```

### Post-Deployment Verification

1. **Infrastructure Check**
   ```bash
   # Verify EC2 instance
   aws ec2 describe-instances --filters "Name=tag:Name,Values=minecraft-server"

   # Check SSM connection
   aws ssm describe-instance-information
   ```

2. **Server Status**
   ```bash
   # Check server logs
   aws ssm send-command \
     --instance-ids "i-1234567890abcdef0" \
     --document-name "AWS-RunShellScript" \
     --parameters 'commands=["tail -n 50 /opt/minecraft/server/logs/latest.log"]'
   ```

### Troubleshooting

1. **Common Issues**
   - SSM Connection: Verify IAM roles and SSM agent installation
   - Mod Deployment: Check mod build artifacts and permissions
   - Server Startup: Review systemd service logs

2. **Logs Location**
   - Minecraft Server: `/opt/minecraft/server/logs/`
   - System Logs: `/var/log/syslog`
   - SSM Logs: `/var/log/amazon/ssm/`

### Security Best Practices

1. **Access Control**
   - Use SSM instead of SSH for server access
   - Implement least privilege IAM policies
   - Regular rotation of AWS credentials

2. **Monitoring**
   - Set up CloudWatch alarms for critical metrics
   - Enable AWS Config for compliance monitoring
   - Regular security audits

3. **Backup Strategy**
   - Automated world backups to S3
   - State file versioning
   - Regular infrastructure validation
