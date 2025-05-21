import json
import base64
import os
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.client('dynamodb')
apigatewaymanagementapi = None

def get_api_client(endpoint_url):
    global apigatewaymanagementapi
    if apigatewaymanagementapi is None:
        apigatewaymanagementapi = boto3.client(
            'apigatewaymanagementapi',
            endpoint_url=endpoint_url
        )
    return apigatewaymanagementapi

def broadcast_audio(connections, audio_data, author, connection_id, endpoint_url):
    api_client = get_api_client(endpoint_url)
    
    # Prepare the message
    message = {
        'action': 'audio',
        'data': {
            'audio': audio_data,
            'author': author,
            'timestamp': datetime.utcnow().isoformat()
        }
    }
    
    # Convert message to JSON
    message_json = json.dumps(message)
    successful_broadcasts = 0
    failed_broadcasts = 0
    deleted_connections = 0
    
    # Check if we're in echo mode (testing)
    is_echo_mode = os.environ.get('ECHO_MODE', 'false').lower() == 'true'
    logger.info(f"Broadcasting in {'echo' if is_echo_mode else 'normal'} mode")
    
    # Broadcast to connections
    for conn in connections:
        # In echo mode, we also send to the source connection
        if is_echo_mode or conn != connection_id:
            try:
                api_client.post_to_connection(
                    Data=message_json,
                    ConnectionId=conn
                )
                successful_broadcasts += 1
                logger.debug(f"Successfully sent message to connection {conn}")
            except Exception as e:
                logger.error(f"Error sending to connection {conn}: {str(e)}")
                if "GoneException" in str(e):
                    # Connection is no longer valid, remove it
                    try:
                        dynamodb.delete_item(
                            TableName=os.environ['CONNECTIONS_TABLE'],
                            Key={'connectionId': {'S': conn}}
                        )
                        deleted_connections += 1
                    except Exception as del_err:
                        logger.error(f"Error deleting connection {conn}: {str(del_err)}")
                else:
                    failed_broadcasts += 1
    
    logger.info(f"Broadcast summary: {successful_broadcasts} successful, {failed_broadcasts} failed, {deleted_connections} stale connections deleted")

def validate_audio_format(audio_data):
    try:
        # Decode base64 data
        decoded_data = base64.b64decode(audio_data)
        
        # Check minimum size (at least 1KB)
        if len(decoded_data) < 1024:
            return False, "Audio data too small"
        
        # Check maximum size (5MB)
        if len(decoded_data) > 5 * 1024 * 1024:
            return False, "Audio data too large"
        
        return True, "Valid audio data"
    except Exception as e:
        return False, f"Invalid audio data: {str(e)}"

def lambda_handler(event, context):
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # EventBridge events come with the detail field directly
        if not isinstance(event.get('detail'), dict):
            logger.error(f"Invalid event structure. Expected detail object, got: {event}")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid event structure'})
            }
        
        detail = event['detail']
        message = detail.get('message', {})
        websocket_context = detail.get('websocket_context', {})
        
        # Validate required fields
        required_fields = {
            'status': detail.get('status'),
            'audio_data': message.get('data'),
            'author': message.get('author'),
            'connection_id': websocket_context.get('connection_id'),
            'endpoint_url': f"https://{websocket_context.get('domain_name')}/{websocket_context.get('stage')}"
        }
        
        # Check for missing fields
        missing_fields = [field for field, value in required_fields.items() if not value]
        if missing_fields:
            error_msg = f"Missing required fields: {', '.join(missing_fields)}"
            logger.error(error_msg)
            return {
                'statusCode': 400,
                'body': json.dumps({'error': error_msg})
            }
        
        # Extract fields for easier access
        status = required_fields['status']
        audio_data = required_fields['audio_data']
        author = required_fields['author']
        connection_id = required_fields['connection_id']
        endpoint_url = required_fields['endpoint_url']
        
        logger.info(f"Processing audio validation for author: {author}, connection: {connection_id}")
        
        # Validate audio format
        is_valid, message = validate_audio_format(audio_data)
        
        if not is_valid:
            logger.error(f"Audio validation failed: {message}")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': message})
            }
        
        # Get all connections for broadcasting
        try:
            response = dynamodb.scan(
                TableName=os.environ['CONNECTIONS_TABLE'],
                ProjectionExpression='connectionId'
            )
            connections = [item['connectionId']['S'] for item in response.get('Items', [])]
            logger.info(f"Found {len(connections)} active connections")
        except Exception as e:
            error_msg = f"Error scanning DynamoDB connections table: {str(e)}"
            logger.error(error_msg)
            return {
                'statusCode': 500,
                'body': json.dumps({'error': error_msg})
            }
        
        # Broadcast the validated audio
        try:
            broadcast_audio(connections, audio_data, author, connection_id, endpoint_url)
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Audio validated and broadcast successfully'
                })
            }
        except Exception as e:
            error_msg = f"Error broadcasting audio: {str(e)}"
            logger.error(error_msg)
            return {
                'statusCode': 500,
                'body': json.dumps({'error': error_msg})
            }
        
    except Exception as e:
        error_msg = f"Error in validate_audio: {str(e)}"
        logger.error(error_msg)
        logger.error(f"Full event: {json.dumps(event)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        } 