import json
import boto3
import os
import logging
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging for CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB resource for storing WebSocket connections
# The table stores connection IDs and their metadata
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('CONNECTIONS_TABLE')
if not table_name:
    logger.error("CONNECTIONS_TABLE environment variable not set")

table = None
if table_name:
    table = dynamodb.Table(table_name)

def get_api_gateway_management_client(event):
    """
    Creates an API Gateway Management API client for WebSocket communication.
    
    This client is used to send messages back to connected clients through
    their WebSocket connections. The endpoint URL is constructed from the
    API Gateway domain and stage provided in the event context.
    
    Args:
        event (dict): The Lambda event containing WebSocket connection details
                     in the requestContext.
    
    Returns:
        boto3.client: API Gateway Management API client, or None if required
                     information is missing.
    """
    domain_name = event.get('requestContext', {}).get('domainName')
    stage = event.get('requestContext', {}).get('stage')
    if not domain_name or not stage:
        return None
    endpoint_url = f"https://{domain_name}/{stage}"
    return boto3.client('apigatewaymanagementapi', endpoint_url=endpoint_url)

def send_pong_response(apigw_client, connection_id):
    """
    Sends a pong response to a client's ping request.
    
    This function implements the WebSocket ping/pong mechanism for connection
    health checks. It sends back a pong message containing the client's
    connection ID and current timestamp.
    
    Args:
        apigw_client (boto3.client): API Gateway Management API client
        connection_id (str): The client's WebSocket connection ID
    
    Returns:
        bool: True if pong was sent successfully, False otherwise
    """
    try:
        response_message = {
            'action': 'pong',
            'data': {
                'connectionId': connection_id,
                'timestamp': datetime.utcnow().isoformat()
            }
        }
        apigw_client.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(response_message)
        )
        return True
    except Exception as e:
        logger.error(f"Pong error: {str(e)}")
        return False

def lambda_handler(event, context):
    """
    Main handler for WebSocket messages in the voice chat system.
    
    This function processes incoming WebSocket messages and handles different
    actions:
    - 'ping': Responds with a pong message for connection health checks
    - 'sendaudio': Processes audio data and sends it to EventBridge for
                   further processing and broadcasting
    
    The function validates the connection context, parses the message body,
    and routes the request to the appropriate handler based on the action.
    
    Flow for audio messages:
    1. Validates connection information and message format
    2. Retrieves all active connections from DynamoDB
    3. Sends the audio event to EventBridge for processing
    4. EventBridge triggers the process_audio Lambda
    
    Args:
        event (dict): Lambda event containing WebSocket message details
        context (LambdaContext): Lambda runtime information
    
    Returns:
        dict: Response object with statusCode and body
    """
    # Extract connection information from the WebSocket context
    request_context = event.get('requestContext', {})
    source_connection_id = request_context.get('connectionId')
    domain = request_context.get('domainName')
    stage = request_context.get('stage')
    
    # Validate required connection information
    if not source_connection_id or not domain or not stage:
        return {'statusCode': 400, 'body': 'Missing connection information'}

    # Ensure DynamoDB table is properly configured
    if not table:
        return {'statusCode': 500, 'body': 'Server configuration error'}

    try:
        # Parse and validate the message body
        message_body = json.loads(event.get('body', '{}'))
        action = message_body.get('action')

        if not action:
            return {'statusCode': 400, 'body': 'No action specified'}

        # Initialize WebSocket API client for responses
        apigw_management_client = get_api_gateway_management_client(event)
        if not apigw_management_client:
            return {'statusCode': 500, 'body': 'API Gateway client initialization failed'}

        # Handle ping/pong for connection health checks
        if action == 'ping':
            if send_pong_response(apigw_management_client, source_connection_id):
                return {'statusCode': 200, 'body': json.dumps({'message': 'Pong sent'})}
            return {'statusCode': 500, 'body': json.dumps({'error': 'Pong failed'})}

        # Handle audio message processing
        if action == 'sendaudio':
            # Retrieve all active WebSocket connections
            try:
                response = table.scan(ProjectionExpression='connectionId')
                connections = response.get('Items', [])
            except Exception as e:
                logger.error(f"DynamoDB error: {str(e)}")
                return {'statusCode': 500, 'body': 'Database error'}

            # Prepare WebSocket context for audio processing
            websocket_context = {
                'domain_name': domain,
                'stage': stage,
                'connection_id': source_connection_id
            }
            
            try:
                # Send audio event to EventBridge for processing
                event_response = boto3.client('events').put_events(
                    Entries=[{
                        'Source': os.environ.get('EVENT_SOURCE', 'voice-chat'),
                        'DetailType': 'SendAudioEvent',
                        'Detail': json.dumps({
                            'status': 'PENDING',
                            'message': message_body,
                            'timestamp': datetime.utcnow().isoformat(),
                            'websocket_context': websocket_context
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME')
                    }]
                )
                logger.info(f"Audio event sent from {source_connection_id}")
                return {
                    'statusCode': 200,
                    'body': json.dumps({'message': 'Audio event sent'})
                }
            except Exception as e:
                logger.error(f"EventBridge error: {str(e)}")
                return {'statusCode': 500, 'body': 'Event processing failed'}
        
        # Return error for unhandled action types
        return {'statusCode': 400, 'body': json.dumps({'error': f'Unhandled action: {action}'})}
        
    except json.JSONDecodeError:
        return {'statusCode': 400, 'body': 'Invalid JSON format'}
    except Exception as e:
        logger.error(f"Message error: {str(e)}")
        return {'statusCode': 500, 'body': 'Message processing failed'}