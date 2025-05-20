import json
import base64
import os

def validate_audio_format(audio_data):
    try:
        # Decode base64 data
        decoded_data = base64.b64decode(audio_data)
        
        # Check minimum size (at least 1KB)
        if len(decoded_data) < 1024:
            return False, "Audio data too small"
        
        # Check maximum size (5MB)
        if len(decoded_data) > 5 * 1024 * 1024:
            return False, "Audio data too large"
        
        return True, "Valid audio data"
    except Exception as e:
        return False, f"Invalid audio data: {str(e)}"

def lambda_handler(event, context):
    try:
        # Parse the message body
        body = json.loads(event['body'])
        audio_data = body.get('data')
        
        if not audio_data:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Audio data is required'})
            }
        
        # Validate audio format
        is_valid, message = validate_audio_format(audio_data)
        
        if not is_valid:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': message})
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Audio data is valid'})
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        } 