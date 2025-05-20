import json
import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('CONNECTIONS_TABLE') # Get table name from environment variable
if not table_name:
    logger.error("DynamoDB connections table name not set in environment variables (CONNECTIONS_TABLE)")
    # Fallback or raise error, depending on desired behavior if env var is missing
    # For now, let's assume it will be set. If not, calls will fail.
table = None
if table_name:
    table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    connection_id = event.get('requestContext', {}).get('connectionId')
    domain_name = event.get('requestContext', {}).get('domainName')
    stage = event.get('requestContext', {}).get('stage')
    
    logger.info(f"Connect event for connectionId: {connection_id}")
    logger.info(f"Domain: {domain_name}, Stage: {stage}")


    if not connection_id:
        logger.error("Connection ID not found in event")
        return {'statusCode': 400, 'body': 'Connection ID not found.'}

    if not table:
        logger.error(f"DynamoDB table {table_name} not initialized.")
        return {'statusCode': 500, 'body': 'Server configuration error.'}

    try:
        table.put_item(
            Item={
                'connectionId': connection_id,
                'connectedAt': context.aws_request_id # Using aws_request_id as a simple timestamp/unique id for connect
                # You might want to add a proper ISO timestamp: datetime.utcnow().isoformat()
                # 'timestamp': datetime.datetime.utcnow().isoformat() # Requires 'import datetime'
            }
        )
        logger.info(f"Connection {connection_id} stored successfully.")
        return {'statusCode': 200, 'body': 'Connected.'}
    except Exception as e:
        logger.error(f"Error storing connection {connection_id}: {str(e)}")
        return {'statusCode': 500, 'body': f"Failed to connect: {str(e)}"}