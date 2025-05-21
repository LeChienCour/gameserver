import json
import boto3
import os
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('CONNECTIONS_TABLE')
if not table_name:
    logger.error("DynamoDB connections table name not set in environment variables (CONNECTIONS_TABLE)")

table = None
if table_name:
    table = dynamodb.Table(table_name)

# Note: The ApiGatewayManagementApi client needs the correct endpoint.
# This endpoint is constructed from the event a Lambda receives from API Gateway when invoked.
# It's usually event['requestContext']['domainName'] + '/' + event['requestContext']['stage']

def get_api_gateway_management_client(event):
    domain_name = event.get('requestContext', {}).get('domainName')
    stage = event.get('requestContext', {}).get('stage')
    if not domain_name or not stage:
        logger.error("Could not determine API Gateway Management endpoint from event.")
        return None
    endpoint_url = f"https://{domain_name}/{stage}"
    logger.info(f"API Gateway Management API endpoint: {endpoint_url}")
    return boto3.client('apigatewaymanagementapi', endpoint_url=endpoint_url)

def broadcast_message(apigw_client, connections, message, source_connection_id=None, table=None):
    """Broadcast a message to all connections except the source."""
    successful_broadcasts = 0
    failed_broadcasts = 0
    deleted_connections = 0
    
    logger.info(f"Starting broadcast to {len(connections)} connections (excluding source: {source_connection_id})")
    
    for connection in connections:
        conn_id = connection['connectionId']
        if conn_id != source_connection_id:
            try:
                apigw_client.post_to_connection(
                    ConnectionId=conn_id,
                    Data=json.dumps(message)
                )
                successful_broadcasts += 1
                logger.debug(f"Successfully sent message to connection {conn_id}")
            except apigw_client.exceptions.GoneException:
                logger.info(f"Connection {conn_id} is stale. Deleting.")
                if table:
                    table.delete_item(Key={'connectionId': conn_id})
                deleted_connections += 1
            except Exception as e:
                logger.error(f"Error posting to connection {conn_id}: {str(e)}")
                failed_broadcasts += 1
    
    logger.info(f"Broadcast summary: {successful_broadcasts} successful, {failed_broadcasts} failed, {deleted_connections} stale connections deleted")

def lambda_handler(event, context):
    # Extract connection information
    request_context = event.get('requestContext', {})
    source_connection_id = request_context.get('connectionId')
    domain = request_context.get('domainName')
    stage = request_context.get('stage')
    
    logger.info(f"Message event from connectionId: {source_connection_id}")
    logger.debug(f"Received event body: {event.get('body')}")

    if not source_connection_id:
        logger.error("Connection ID not found in event for message handler.")
        return {'statusCode': 400, 'body': 'Connection ID missing.'}

    if not table:
        logger.error(f"DynamoDB table {table_name} not initialized for message handler.")
        return {'statusCode': 500, 'body': 'Server configuration error.'}

    try:
        message_body = json.loads(event.get('body', '{}'))
        action = message_body.get('action')

        if not action:
            logger.error("No action specified in message")
            return {'statusCode': 400, 'body': 'No action specified'}

        # Get all active connections
        try:
            response = table.scan(ProjectionExpression='connectionId')
            connections = response.get('Items', [])
            logger.info(f"Found {len(connections)} active connections")
        except Exception as e:
            logger.error(f"Error scanning DynamoDB connections table: {str(e)}")
            return {'statusCode': 500, 'body': 'Could not retrieve connections.'}

        # Initialize API Gateway Management client
        apigw_management_client = get_api_gateway_management_client(event)
        if not apigw_management_client:
            return {'statusCode': 500, 'body': 'Could not initialize API Gateway Management client.'}

        # Construct endpoint URL for WebSocket API
        endpoint_url = f"https://{domain}/{stage}"

        # Send event to EventBridge
        eventbridge = boto3.client('events')
        logger.info(f"Sending event to EventBridge: {message_body}")
        try:
            event_response = eventbridge.put_events(
                Entries=[{
                    'Source': os.environ.get('EVENT_SOURCE', 'voice-chat'),
                    'DetailType': 'SendAudioEvent',
                    'Detail': json.dumps({
                        'status': 'PENDING',
                        'message': message_body,
                        'timestamp': datetime.utcnow().isoformat(),
                        'connection_id': source_connection_id,
                        'endpoint_url': endpoint_url,
                        'websocket_context': {
                            'domain_name': domain,
                            'stage': stage,
                            'connection_id': source_connection_id
                        }
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME')
                }]
            )
            logger.info(f"Successfully sent event to EventBridge. Response: {event_response}")
        except Exception as e:
            logger.error(f"Failed to send event to EventBridge: {str(e)}")
            raise  # Re-raise the exception to be caught by the outer try-catch
        
        # Broadcast message to other clients
        broadcast_message(
            apigw_management_client,
            connections,
            message_body,
            source_connection_id,
            table
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed',
                'eventbridge_response': event_response
            })
        }

    except json.JSONDecodeError:
        logger.error(f"Invalid JSON received from {source_connection_id}: {event.get('body')}")
        return {'statusCode': 400, 'body': 'Invalid JSON format.'}
    except Exception as e:
        logger.error(f"Error processing message from {source_connection_id}: {str(e)}")
        logger.error(event)
        return {'statusCode': 500, 'body': f"Error processing message: {str(e)}"}