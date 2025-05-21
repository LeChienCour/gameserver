import json
import boto3
import base64
import os
from datetime import datetime
import logging

s3 = boto3.client('s3')
eventbridge = boto3.client('events')
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Validate required environment variables
def validate_env_vars():
    """Validate required environment variables are set"""
    required_vars = ['AUDIO_BUCKET']
    missing_vars = [var for var in required_vars if not os.environ.get(var)]
    if missing_vars:
        raise ValueError(f"Missing required environment variables: {', '.join(missing_vars)}")

def get_websocket_context(event):
    """Extract WebSocket context from either direct WebSocket event or EventBridge event"""
    if 'requestContext' in event:
        # Direct WebSocket event
        request_context = event.get('requestContext', {})
        return {
            'domain_name': request_context.get('domainName'),
            'stage': request_context.get('stage'),
            'connection_id': request_context.get('connectionId')
        }
    elif 'detail' in event:
        # EventBridge event
        detail = event.get('detail', {})
        if isinstance(detail, str):
            detail = json.loads(detail)
        
        websocket_context = detail.get('websocket_context', {})
        if websocket_context:
            return {
                'domain_name': websocket_context.get('domain_name'),
                'stage': websocket_context.get('stage'),
                'connection_id': websocket_context.get('connection_id')
            }
    
    return None

def get_audio_data(event):
    """Extract audio data from either WebSocket or EventBridge event"""
    if 'body' in event:
        # WebSocket event
        try:
            body = json.loads(event.get('body', '{}'))
            return {
                'audio_data': body.get('data'),
                'author': body.get('author', 'Anonymous')
            }
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in WebSocket message: {str(e)}")
            return None
    elif 'detail' in event:
        # EventBridge event
        detail = event.get('detail', {})
        if isinstance(detail, str):
            detail = json.loads(detail)
        
        message = detail.get('message', {})
        if isinstance(message, str):
            message = json.loads(message)
            
        return {
            'audio_data': message.get('data'),
            'author': message.get('author', 'Anonymous')
        }
    
    return None

def lambda_handler(event, context):
    """Main handler that processes audio from both WebSocket and EventBridge events"""
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Validate environment variables
        validate_env_vars()
        
        # Get WebSocket context
        ws_context = get_websocket_context(event)
        if not ws_context or not all([ws_context['domain_name'], ws_context['stage'], ws_context['connection_id']]):
            logger.error("Missing required WebSocket context")
            return {
                'statusCode': 400,
                'body': 'Missing WebSocket context'
            }
            
        # Get audio data
        audio_info = get_audio_data(event)
        if not audio_info or not audio_info['audio_data']:
            logger.error("Missing required audio data")
            return {
                'statusCode': 400,
                'body': 'Audio data is required'
            }
            
        # Store audio in S3
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        s3_key = f"audio/{audio_info['author']}/{timestamp}.pcm"
        
        try:
            s3.put_object(
                Bucket=os.environ['AUDIO_BUCKET'],
                Key=s3_key,
                Body=base64.b64decode(audio_info['audio_data'])
            )
            logger.info(f"Successfully stored audio in S3: {s3_key}")
        except Exception as e:
            logger.error(f"Error storing audio in S3: {str(e)}")
            return {'statusCode': 500, 'body': 'Error storing audio'}
        
        # Send event to validation
        try:
            event_detail = {
                'status': 'PENDING',
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
            }
            
            # Add EventBusName only if specified, otherwise use default event bus
            event_bus_name = os.environ.get('EVENT_BUS_NAME')
            if event_bus_name:
                event_entry['EventBusName'] = event_bus_name
            
            event_response = eventbridge.put_events(Entries=[event_entry])
            logger.info(f"Successfully sent event for validation. Response: {event_response}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Audio stored and sent for validation',
                    's3_key': s3_key
                })
            }
        except Exception as e:
            error_msg = f"Error sending event for validation: {str(e)}"
            logger.error(error_msg)
            return {
                'statusCode': 500,
                'body': json.dumps({'error': error_msg})
            }
            
    except Exception as e:
        error_msg = f"Error in lambda_handler: {str(e)}"
        logger.error(error_msg)
        logger.error(f"Full event: {json.dumps(event)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        } 