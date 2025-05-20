import json
import boto3
import base64
import os
from datetime import datetime

dynamodb = boto3.client('dynamodb')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')
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
    
    # Broadcast to all connections except sender
    for conn in connections:
        if conn != connection_id:  # Don't send back to sender
            try:
                api_client.post_to_connection(
                    Data=message_json,
                    ConnectionId=conn
                )
            except Exception as e:
                print(f"Error sending to connection {conn}: {str(e)}")
                if "GoneException" in str(e):
                    # Connection is no longer valid, remove it
                    try:
                        dynamodb.delete_item(
                            TableName=os.environ['CONNECTIONS_TABLE'],
                            Key={'connectionId': {'S': conn}}
                        )
                    except Exception as del_err:
                        print(f"Error deleting connection {conn}: {str(del_err)}")

def lambda_handler(event, context):
    # Extract connection information
    domain = event['requestContext']['domainName']
    stage = event['requestContext']['stage']
    connection_id = event['requestContext']['connectionId']
    endpoint_url = f"https://{domain}/{stage}"
    
    try:
        # Parse the message body
        body = json.loads(event['body'])
        audio_data = body.get('data')
        author = body.get('author', 'Anonymous')
        
        if not audio_data:
            return {'statusCode': 400, 'body': 'Audio data is required'}
        
        # Store audio in S3
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        s3_key = f"audio/{author}/{timestamp}.pcm"
        
        try:
            s3.put_object(
                Bucket=os.environ['AUDIO_BUCKET'],
                Key=s3_key,
                Body=base64.b64decode(audio_data)
            )
        except Exception as e:
            print(f"Error storing audio in S3: {str(e)}")
            return {'statusCode': 500, 'body': 'Error storing audio'}
        
        # Publish event to EventBridge
        event_response = eventbridge.put_events(
            Entries=[{
                'Source': os.environ.get('EVENT_SOURCE', 'game-server.audio'),
                'DetailType': 'SendAudioEvent',
                'Detail': json.dumps({
                    'status': 'PENDING',
                    'author': author,
                    's3_key': s3_key,
                    'timestamp': datetime.utcnow().isoformat()
                }),
                'EventBusName': os.environ['EVENT_BUS_NAME']
            }]
        )
        
        # Get all connections
        response = dynamodb.scan(
            TableName=os.environ['CONNECTIONS_TABLE'],
            ProjectionExpression='connectionId'
        )
        connections = [item['connectionId']['S'] for item in response.get('Items', [])]
        
        # Broadcast the audio to all other connections
        broadcast_audio(connections, audio_data, author, connection_id, endpoint_url)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Audio processed and broadcast successfully',
                'eventbridge_response': event_response
            })
        }
        
    except Exception as e:
        print(f"Error processing audio: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        } 