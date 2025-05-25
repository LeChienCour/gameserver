import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('CONNECTIONS_TABLE')
if not table_name:
    logger.error("DynamoDB connections table name not set in environment variables (CONNECTIONS_TABLE)")
table = None
if table_name:
    table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    # Log the full event for debugging
    logger.info(f"Received disconnect event: {json.dumps(event)}")
    
    connection_id = event.get('requestContext', {}).get('connectionId')
    logger.info(f"Disconnect event for connectionId: {connection_id}")
    logger.info(f"Using DynamoDB table: {table_name}")

    if not connection_id:
        logger.error("Connection ID not found in event")
        return {'statusCode': 400, 'body': 'Connection ID not found.'}

    if not table:
        logger.error(f"DynamoDB table {table_name} not initialized.")
        return {'statusCode': 500, 'body': 'Server configuration error.'}

    try:
        # Check if connection exists before deleting
        try:
            get_response = table.get_item(Key={'connectionId': connection_id})
            if 'Item' in get_response:
                logger.info(f"Found existing connection to delete: {json.dumps(get_response['Item'])}")
            else:
                logger.warning(f"No existing connection found for ID: {connection_id}")
        except Exception as ge:
            logger.error(f"Error checking existing connection: {str(ge)}")
        
        # Delete the connection
        delete_response = table.delete_item(
            Key={
                'connectionId': connection_id
            },
            ReturnValues='ALL_OLD'  # This will return the deleted item
        )
        
        # Log the deleted item if it existed
        if 'Attributes' in delete_response:
            logger.info(f"Successfully deleted connection: {json.dumps(delete_response['Attributes'])}")
        else:
            logger.warning(f"No connection found to delete for ID: {connection_id}")
        
        # Verify deletion
        try:
            verification = table.get_item(Key={'connectionId': connection_id})
            if 'Item' not in verification:
                logger.info(f"Successfully verified connection deletion for {connection_id}")
            else:
                logger.warning(f"Connection still exists after deletion attempt: {json.dumps(verification['Item'])}")
        except Exception as ve:
            logger.error(f"Error verifying connection deletion: {str(ve)}")
        
        return {'statusCode': 200, 'body': 'Disconnected.'}
    except Exception as e:
        logger.error(f"Error deleting connection {connection_id}: {str(e)}")
        return {'statusCode': 500, 'body': f"Failed to disconnect: {str(e)}"}