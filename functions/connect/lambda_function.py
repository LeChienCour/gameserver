import json
import boto3
import os
import logging
from datetime import datetime

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
    # Log the full event for debugging
    logger.info(f"Received connect event: {json.dumps(event)}")
    
    connection_id = event.get('requestContext', {}).get('connectionId')
    domain_name = event.get('requestContext', {}).get('domainName')
    stage = event.get('requestContext', {}).get('stage')
    
    logger.info(f"Connect event for connectionId: {connection_id}")
    logger.info(f"Domain: {domain_name}, Stage: {stage}")
    logger.info(f"Using DynamoDB table: {table_name}")

    if not connection_id:
        logger.error("Connection ID not found in event")
        return {'statusCode': 400, 'body': 'Connection ID not found.'}

    if not table:
        logger.error(f"DynamoDB table {table_name} not initialized.")
        return {'statusCode': 500, 'body': 'Server configuration error.'}

    try:
        # Create connection record with timestamp
        connection_item = {
            'connectionId': connection_id,
            'connectedAt': datetime.utcnow().isoformat(),
            'domain': domain_name,
            'stage': stage
        }
        
        logger.info(f"Storing connection item: {json.dumps(connection_item)}")
        
        table.put_item(Item=connection_item)
        
        # Verify the connection was stored
        try:
            verification = table.get_item(Key={'connectionId': connection_id})
            if 'Item' in verification:
                logger.info(f"Successfully verified connection storage: {json.dumps(verification['Item'])}")
            else:
                logger.warning(f"Connection verification failed - item not found after storage")
        except Exception as ve:
            logger.error(f"Error verifying connection storage: {str(ve)}")
        
        logger.info(f"Connection {connection_id} stored successfully.")
        return {'statusCode': 200, 'body': 'Connected.'}
    except Exception as e:
        logger.error(f"Error storing connection {connection_id}: {str(e)}")
        return {'statusCode': 500, 'body': f"Failed to connect: {str(e)}"}