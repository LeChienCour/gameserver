import json
import base64
import os
import boto3
import logging
from datetime import datetime

# Configure logging for CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS service clients
dynamodb = boto3.client('dynamodb')
apigatewaymanagementapi = None

def get_api_client(endpoint_url):
    """
    Creates or retrieves a cached API Gateway Management API client.
    
    This function maintains a single client instance for the WebSocket API
    to optimize performance and resource usage. The client is used to send
    messages back to connected clients through their WebSocket connections.
    
    Args:
        endpoint_url (str): The WebSocket API endpoint URL
                          (format: https://{domain}/{stage})
    
    Returns:
        boto3.client: API Gateway Management API client
    
    Raises:
        Exception: If client creation fails
    """
    global apigatewaymanagementapi
    if apigatewaymanagementapi is None:
        try:
            apigatewaymanagementapi = boto3.client(
                'apigatewaymanagementapi',
                endpoint_url=endpoint_url
            )
        except Exception as e:
            logger.error(f"API Gateway client error: {str(e)}")
            raise
    return apigatewaymanagementapi

def broadcast_audio(connections, audio_data, author, connection_id, endpoint_url):
    """
    Broadcasts audio data to all connected clients except the sender.
    
    This function handles the distribution of processed audio data to all
    active WebSocket connections. It includes special handling for echo mode
    and manages connection cleanup for stale connections.
    
    The broadcast process:
    1. Prepares the audio message with metadata
    2. Attempts to send to each connection
    3. Handles failed sends and cleans up stale connections
    4. Tracks broadcast statistics
    
    Args:
        connections (list): List of connection IDs to broadcast to
        audio_data (str): Base64 encoded audio data
        author (str): Identifier of the audio source client
        connection_id (str): WebSocket connection ID of the sender
        endpoint_url (str): WebSocket API endpoint URL
    
    Returns:
        tuple: (message_sent, successful_broadcasts, failed_broadcasts, deleted_connections)
    """
    api_client = get_api_client(endpoint_url)
    
    message = {
        'action': 'audio',
        'data': {
            'audio': audio_data,
            'author': author,
            'timestamp': datetime.utcnow().isoformat()
        }
    }
    
    message_json = json.dumps(message)
    successful_broadcasts = 0
    failed_broadcasts = 0
    deleted_connections = 0
    
    is_echo_mode = os.environ.get('ECHO_MODE', 'false').lower() == 'true'
    single_connection = len(connections) == 1 and connections[0] == connection_id
    
    # If there's only one connection and it's the sender, force echo mode
    if single_connection:
        is_echo_mode = True
        logger.info("Single connection detected, forcing echo mode")
    
    logger.info(f"Broadcasting to {len(connections)} connections (Echo mode: {is_echo_mode})")
    logger.info(f"Source connection: {connection_id}")
    
    for conn in connections:
        logger.info(f"Processing connection: {conn}")
        
        # Check if we should broadcast to this connection
        should_broadcast = is_echo_mode or conn != connection_id
        if not should_broadcast:
            logger.info(f"Skipping source connection {conn}")
            continue
            
        try:
            api_client.post_to_connection(
                Data=message_json,
                ConnectionId=conn
            )
            successful_broadcasts += 1
            logger.info(f"Successfully sent to {conn}")
        except Exception as e:
            error_msg = str(e)
            if "GoneException" in error_msg:
                try:
                    dynamodb.delete_item(
                        TableName=os.environ['CONNECTIONS_TABLE'],
                        Key={'connectionId': {'S': conn}}
                    )
                    deleted_connections += 1
                    logger.info(f"Deleted stale connection: {conn}")
                except Exception as del_err:
                    logger.error(f"Connection deletion error: {str(del_err)}")
            else:
                failed_broadcasts += 1
                logger.error(f"Broadcast error for {conn}: {error_msg}")
    
    # Log final statistics
    logger.info(
        f"Broadcast complete - Total: {len(connections)}, "
        f"Success: {successful_broadcasts}, Failed: {failed_broadcasts}, "
        f"Deleted: {deleted_connections}, Echo mode: {is_echo_mode}"
    )
    return message, successful_broadcasts, failed_broadcasts, deleted_connections

def validate_audio_format(audio_data):
    """
    Validates the format and size of audio data.
    
    Performs basic validation on the audio data:
    1. Verifies it's valid base64 encoded data
    2. Checks minimum size (1KB) to ensure it's not empty/corrupted
    3. Checks maximum size (5MB) to prevent oversized payloads
    
    Args:
        audio_data (str): Base64 encoded audio data to validate
    
    Returns:
        tuple: (is_valid, message)
            - is_valid (bool): Whether the audio data is valid
            - message (str): Description of validation result or error
    """
    try:
        decoded_data = base64.b64decode(audio_data)
        if len(decoded_data) < 1024:
            return False, "Audio data too small"
        if len(decoded_data) > 5 * 1024 * 1024:
            return False, "Audio data too large"
        return True, "Valid audio data"
    except Exception as e:
        return False, f"Invalid audio data: {str(e)}"

def lambda_handler(event, context):
    """
    Main handler for audio validation and broadcasting.
    
    This function is triggered by EventBridge events after audio processing.
    It validates the processed audio data and broadcasts it to all connected
    clients through their WebSocket connections.
    
    Flow:
    1. Retrieves active connections from DynamoDB
    2. Validates event structure and required fields
    3. Validates audio format
    4. Broadcasts valid audio to all connected clients
    5. Handles connection cleanup and error cases
    
    Args:
        event (dict): EventBridge event containing processed audio data
        context (LambdaContext): Lambda runtime information
    
    Returns:
        dict: Response object with statusCode and body containing broadcast results
    """
    try:
        connections_table = os.environ.get('CONNECTIONS_TABLE')
        logger.info(f"Using connections table: {connections_table}")
        
        try:
            # Scan for active connections
            response = dynamodb.scan(
                TableName=connections_table,
                ProjectionExpression='connectionId'
            )
            
            # Extract and validate connection IDs
            connections = []
            for item in response.get('Items', []):
                conn_id = item.get('connectionId', {}).get('S')
                if conn_id:
                    connections.append(conn_id)
                else:
                    logger.warning(f"Invalid connection item format: {item}")
            
            logger.info(f"Found {len(connections)} active connections")
            if connections:
                logger.info(f"Connection IDs: {connections}")
            
            if not connections:
                return {
                    'statusCode': 200,
                    'body': json.dumps({'message': 'No active connections'})
                }
            
        except Exception as e:
            logger.error(f"DynamoDB scan error: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Database error'})
            }
        
        # Validate event structure
        if not isinstance(event.get('detail'), dict):
            logger.error(f"Invalid event structure: {event}")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid event structure'})
            }
        
        detail = event['detail']
        message = detail.get('message', {})
        websocket_context = detail.get('websocket_context', {})
        
        # Log incoming event details
        logger.info(f"Event detail: {json.dumps(detail)}")
        logger.info(f"WebSocket context: {json.dumps(websocket_context)}")
        
        required_fields = {
            'status': detail.get('status'),
            'audio_data': message.get('data'),
            'author': message.get('author'),
            'connection_id': websocket_context.get('connection_id'),
            'domain_name': websocket_context.get('domain_name'),
            'stage': websocket_context.get('stage')
        }
        
        missing_fields = [field for field, value in required_fields.items() if not value]
        if missing_fields:
            logger.error(f"Missing required fields: {missing_fields}")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f"Missing fields: {', '.join(missing_fields)}"})
            }
        
        status = required_fields['status']
        audio_data = required_fields['audio_data']
        author = required_fields['author']
        connection_id = required_fields['connection_id']
        endpoint_url = f"https://{required_fields['domain_name']}/{required_fields['stage']}"
        
        logger.info(f"Processing audio from {author} (connection: {connection_id})")
        logger.info(f"Using endpoint URL: {endpoint_url}")
        
        is_valid, validation_message = validate_audio_format(audio_data)
        if not is_valid:
            logger.error(f"Audio validation failed: {validation_message}")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': validation_message})
            }
        
        try:
            sent_payload, successes, failures, deletions = broadcast_audio(
                connections, 
                audio_data, 
                author, 
                connection_id, 
                endpoint_url
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Audio broadcast complete',
                    'statistics': {
                        'total_connections': len(connections),
                        'successful': successes,
                        'failed': failures,
                        'deleted': deletions
                    }
                })
            }
        except Exception as e:
            logger.error(f"Broadcast error: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Broadcast failed'})
            }
        
    except Exception as e:
        logger.error(f"Validation error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        } 