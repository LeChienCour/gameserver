import json
import boto3
import os
import logging
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('CONNECTIONS_TABLE')
if not table_name:
    logger.error("CONNECTIONS_TABLE environment variable not set")
    raise ValueError("CONNECTIONS_TABLE environment variable not set")
table = dynamodb.Table(table_name)

def get_api_client(domain_name, stage):
    """
    Create an API Gateway Management API client for sending messages back to clients
    """
    endpoint_url = f"https://{domain_name}/{stage}"
    return boto3.client(
        'apigatewaymanagementapi',
        endpoint_url=endpoint_url
    )

def update_connection_info(connection_id, username, timestamp):
    """
    Update the connection record in DynamoDB with username and timestamp
    """
    try:
        table.update_item(
            Key={'connection_id': connection_id},
            UpdateExpression='SET username = :u, connect_timestamp = :t',
            ExpressionAttributeValues={
                ':u': username,
                ':t': timestamp
            }
        )
        logger.info(f"Updated connection info for connection_id: {connection_id}, username: {username}")
        return True
    except ClientError as e:
        logger.error(f"Failed to update connection info: {str(e)}")
        return False

def send_response(api_client, connection_id, message):
    """
    Send a response message back to the client
    """
    try:
        api_client.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(message)
        )
        logger.info(f"Successfully sent response to connection_id: {connection_id}")
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == 'GoneException':
            logger.warning(f"Connection {connection_id} is gone, removing from database")
            try:
                table.delete_item(Key={'connection_id': connection_id})
            except ClientError as delete_error:
                logger.error(f"Failed to delete gone connection: {str(delete_error)}")
        else:
            logger.error(f"Failed to send message to connection {connection_id}: {str(e)}")
        return False

def lambda_handler(event, context):
    """
    Handle WebSocket connection message
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Extract connection details from event
        connection_id = event['requestContext']['connectionId']
        domain_name = event['requestContext']['domainName']
        stage = event['requestContext']['stage']
        
        # Parse message body
        body = json.loads(event['body'])
        action = body.get('action')
        username = body.get('username')
        timestamp = body.get('timestamp')
        
        # Validate message
        if not all([action, username, timestamp]):
            logger.error("Missing required fields in message")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing required fields'})
            }
        
        if action != 'connect':
            logger.error(f"Invalid action: {action}")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Invalid action'})
            }
        
        # Initialize API client
        api_client = get_api_client(domain_name, stage)
        
        # Update connection info in DynamoDB
        if not update_connection_info(connection_id, username, timestamp):
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Failed to update connection info'})
            }
        
        # Prepare and send response
        response_message = {
            'action': 'connectack',
            'data': {
                'connectionId': connection_id
            }
        }
        
        if not send_response(api_client, connection_id, response_message):
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'Failed to send response'})
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Connection processed successfully'})
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse message body: {str(e)}")
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid JSON in message body'})
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        } 