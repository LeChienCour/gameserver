import json
import boto3
import base64
import os
from datetime import datetime
import logging

# Configure logging for CloudWatch
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Initialize AWS service clients
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

def validate_env_vars():
    """
    Validates required environment variables are set.
    
    This function checks for the presence of required environment variables
    that are needed for the function to operate correctly. Currently checks
    for:
    - AUDIO_BUCKET: S3 bucket for storing audio files
    
    Raises:
        ValueError: If any required environment variables are missing
    """
    required_vars = ['AUDIO_BUCKET']
    missing_vars = [var for var in required_vars if not os.environ.get(var)]
    if missing_vars:
        raise ValueError(f"Missing required environment variables: {', '.join(missing_vars)}")

def get_websocket_context(event):
    """
    Extracts WebSocket context from either direct WebSocket or EventBridge events.
    
    This function handles two types of events:
    1. Direct WebSocket events from API Gateway
    2. EventBridge events containing WebSocket context
    
    The context includes:
    - domain_name: API Gateway domain
    - stage: API deployment stage
    - connection_id: Client's WebSocket connection ID
    
    Args:
        event (dict): Lambda event from either source
    
    Returns:
        dict: WebSocket context information, or None if not found
    """
    if 'requestContext' in event:
        request_context = event.get('requestContext', {})
        context = {
            'domain_name': request_context.get('domainName'),
            'stage': request_context.get('stage'),
            'connection_id': request_context.get('connectionId')
        }
        return context
    elif 'detail' in event:
        detail = event.get('detail', {})
        return detail.get('websocket_context', {})
    return None

def get_audio_data(event):
    """
    Extracts audio data from either WebSocket or EventBridge events.
    
    This function handles audio data extraction and validation from:
    1. Direct WebSocket messages
    2. EventBridge events containing audio data
    
    The function performs basic validation:
    - Ensures audio data is present
    - Validates base64 encoding
    - Extracts author information
    
    Args:
        event (dict): Lambda event containing audio data
    
    Returns:
        dict: Dictionary containing audio_data and author, or None if invalid
    """
    if 'detail' in event:
        detail = event.get('detail', {})
        message = detail.get('message', {})
        audio_data = {
            'audio_data': message.get('data'),
            'author': message.get('author', 'Anonymous')
        }
    else:
        try:
            body = json.loads(event.get('body', '{}'))
            audio_data = {
                'audio_data': body.get('data'),
                'author': body.get('author', 'Anonymous')
            }
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in WebSocket message: {str(e)}")
            return None
    
    if not audio_data.get('audio_data'):
        return None
    
    try:
        base64.b64decode(audio_data['audio_data'])
        return audio_data
    except Exception as e:
        logger.error(f"Invalid base64 audio data: {str(e)}")
        return None

def lambda_handler(event, context):
    """
    Main handler for audio processing in the voice chat system.
    
    This function processes audio data from WebSocket connections:
    1. Validates environment configuration
    2. Extracts and validates WebSocket context
    3. Processes and stores audio data in S3
    4. Sends processed audio event to EventBridge for broadcasting
    
    The function handles both direct WebSocket events and EventBridge events,
    maintaining the WebSocket context throughout the processing pipeline.
    
    Flow:
    1. Validate environment and extract context
    2. Extract and validate audio data
    3. Store audio in S3 with metadata
    4. Send processed event to EventBridge for broadcasting
    
    Args:
        event (dict): Lambda event containing audio data and context
        context (LambdaContext): Lambda runtime information
    
    Returns:
        dict: Response object with statusCode and body
    """
    try:
        validate_env_vars()
        
        ws_context = get_websocket_context(event)
        if not ws_context or not all([ws_context.get('domain_name'), ws_context.get('stage'), ws_context.get('connection_id')]):
            error_msg = f"Missing WebSocket context fields: {list(ws_context.keys()) if ws_context else 'None'}"
            logger.error(error_msg)
            return {
                'statusCode': 400,
                'body': json.dumps({'error': error_msg})
            }
            
        audio_info = get_audio_data(event)
        if not audio_info:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid or missing audio data'})
            }
            
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        s3_key = f"audio/{audio_info['author']}/{timestamp}.pcm"
        
        try:
            s3.put_object(
                Bucket=os.environ['AUDIO_BUCKET'],
                Key=s3_key,
                Body=base64.b64decode(audio_info['audio_data'])
            )
            logger.info(f"Audio stored: {s3_key}")
        except Exception as e:
            logger.error(f"S3 storage error: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Error storing audio'})
            }
        
        try:
            event_detail = {
                'status': 'PROCESSED',
                'message': {
                    'action': 'sendaudio',
                    'data': audio_info['audio_data'],
                    'author': audio_info['author']
                },
                'websocket_context': ws_context,
                's3_key': s3_key,
                'timestamp': datetime.utcnow().isoformat()
            }
            
            event_entry = {
                'Source': os.environ.get('EVENT_SOURCE', 'voice-chat'),
                'DetailType': 'SendAudioEvent',
                'Detail': json.dumps(event_detail),
                'EventBusName': os.environ.get('EVENT_BUS_NAME')
            }
            
            eventbridge.put_events(Entries=[event_entry])
            logger.info(f"Audio validation event sent for {s3_key}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Audio processed',
                    's3_key': s3_key
                })
            }
        except Exception as e:
            logger.error(f"EventBridge error: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Error sending validation event'})
            }
            
    except Exception as e:
        logger.error(f"Process audio error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        } 