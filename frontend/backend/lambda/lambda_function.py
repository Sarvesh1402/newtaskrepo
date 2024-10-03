import json
import boto3
from decimal import Decimal
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Helper function to handle Decimal objects
def decimal_to_int_or_float(value):
    if isinstance(value, Decimal):
        if value % 1 == 0:
            return int(value)
        return float(value)
    return value

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event, default=str)}")

    query_params = event.get('queryStringParameters', {}) or {}
    visitor_id = query_params.get('visitor', 'unknown_visitor')

    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('visitor_count')

    try:
        logger.info(f"Visitor ID: {visitor_id}")

        # Check if the item exists
        response = table.get_item(Key={'counterid': visitor_id})

        if 'Item' not in response:
            logger.info(f"Initializing visitor count for {visitor_id}")
            table.put_item(Item={'counterid': visitor_id, 'visitorCount': Decimal(0)})

        # Update the visitor count
        response = table.update_item(
            Key={'counterid': visitor_id},
            UpdateExpression='ADD visitorCount :inc',
            ExpressionAttributeValues={':inc': Decimal(1)},
            ReturnValues="UPDATED_NEW"
        )

        visitor_count = decimal_to_int_or_float(response['Attributes']['visitorCount'])

        logger.info(f"Update response: {json.dumps(response, default=str)}")

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({'visitorCount': visitor_count})
        }

    except Exception as e:
        logger.error(f"Error updating DynamoDB: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({'error': str(e)})
        }
