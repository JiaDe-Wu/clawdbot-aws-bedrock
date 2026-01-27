"""
Clawdbot Bedrock Pre-Check Lambda Function
Validates Bedrock access and model availability before deployment
"""

import json
import boto3
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    CloudFormation Custom Resource handler
    Validates Bedrock environment before Clawdbot deployment
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Import cfnresponse inline (available in Lambda environment)
    import urllib3
    http = urllib3.PoolManager()
    
    def send_response(event, context, status, data):
        response_body = {
            'Status': status,
            'Reason': f'See CloudWatch Log Stream: {context.log_stream_name}',
            'PhysicalResourceId': context.log_stream_name,
            'StackId': event['StackId'],
            'RequestId': event['RequestId'],
            'LogicalResourceId': event['LogicalResourceId'],
            'Data': data
        }
        
        json_response = json.dumps(response_body)
        headers = {'content-type': '', 'content-length': str(len(json_response))}
        
        try:
            http.request('PUT', event['ResponseURL'], body=json_response, headers=headers)
        except Exception as e:
            logger.error(f"Failed to send response: {e}")
    
    try:
        request_type = event.get('RequestType')
        
        # Handle Delete - no action needed
        if request_type == 'Delete':
            send_response(event, context, 'SUCCESS', {'Message': 'Delete completed'})
            return
        
        # Get parameters
        model_id = event.get('ResourceProperties', {}).get('ModelId', 
                            'anthropic.claude-3-5-sonnet-20241022-v2:0')
        
        # Initialize AWS clients
        bedrock = boto3.client('bedrock')
        bedrock_runtime = boto3.client('bedrock-runtime')
        
        results = {
            'checks_passed': 0,
            'checks_failed': 0,
            'model_id': model_id
        }
        
        # Check 1: Bedrock service availability
        logger.info("Check 1/3: Bedrock service availability")
        try:
            bedrock.list_foundation_models(byProvider='Anthropic')
            results['bedrock_available'] = True
            results['checks_passed'] += 1
            logger.info("✓ Bedrock service is available")
        except ClientError as e:
            logger.error(f"✗ Bedrock service check failed: {e}")
            send_response(event, context, 'FAILED', 
                        {'Error': 'Bedrock service not available in this region. Use us-east-1 or us-west-2.'})
            return
        
        # Check 2: Model access and status
        logger.info(f"Check 2/3: Model access for {model_id}")
        try:
            models_response = bedrock.list_foundation_models(byProvider='Anthropic')
            available_models = {m['modelId']: m for m in models_response.get('modelSummaries', [])}
            
            if model_id not in available_models:
                logger.error(f"✗ Model {model_id} not found")
                send_response(event, context, 'FAILED',
                            {'Error': f'Model {model_id} not found. Check model ID or region.'})
                return
            
            model_info = available_models[model_id]
            model_status = model_info.get('modelLifecycle', {}).get('status', 'UNKNOWN')
            
            if model_status != 'ACTIVE':
                logger.error(f"✗ Model {model_id} status is {model_status}, not ACTIVE")
                send_response(event, context, 'FAILED',
                            {'Error': f'Model {model_id} is not enabled. Go to Bedrock Console → Model access → Enable this model.'})
                return
            
            results['model_status'] = model_status
            results['checks_passed'] += 1
            logger.info(f"✓ Model {model_id} is ACTIVE")
            
        except ClientError as e:
            logger.error(f"✗ Model access check failed: {e}")
            send_response(event, context, 'FAILED',
                        {'Error': f'Failed to check model access: {str(e)}'})
            return
        
        # Check 3: Test model invocation
        logger.info(f"Check 3/3: Testing model invocation")
        try:
            test_body = json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 10,
                "messages": [{"role": "user", "content": "test"}]
            })
            
            response = bedrock_runtime.invoke_model(
                modelId=model_id,
                body=test_body,
                contentType='application/json',
                accept='application/json'
            )
            
            response_body = json.loads(response['body'].read())
            results['model_invocation'] = 'SUCCESS'
            results['checks_passed'] += 1
            logger.info(f"✓ Model invocation successful")
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            error_message = e.response['Error']['Message']
            logger.error(f"✗ Model invocation failed: {error_code} - {error_message}")
            send_response(event, context, 'FAILED',
                        {'Error': f'Model invocation failed: {error_message}. Check IAM permissions.'})
            return
        
        # All checks passed
        response_data = {
            'Message': 'All pre-checks passed successfully',
            'ChecksPassed': results['checks_passed'],
            'ModelId': model_id,
            'ModelStatus': model_status
        }
        
        logger.info(f"✓ All checks passed: {response_data}")
        send_response(event, context, 'SUCCESS', response_data)
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        send_response(event, context, 'FAILED',
                    {'Error': f'Unexpected error: {str(e)}'})
