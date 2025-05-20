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
    connection_id = event.get('requestContext', {}).get('connectionId')
    logger.info(f"Disconnect event for connectionId: {connection_id}")

    if not connection_id:
        logger.error("Connection ID not found in event")
        return {'statusCode': 400, 'body': 'Connection ID not found.'}

    if not table:
        logger.error(f"DynamoDB table {table_name} not initialized.")
        return {'statusCode': 500, 'body': 'Server configuration error.'}

    try:
        table.delete_item(
            Key={
                'connectionId': connection_id
            }
        )
        logger.info(f"Connection {connection_id} deleted successfully.")
        return {'statusCode': 200, 'body': 'Disconnected.'}
    except Exception as e:
        logger.error(f"Error deleting connection {connection_id}: {str(e)}")
        return {'statusCode': 500, 'body': f"Failed to disconnect: {str(e)}"}