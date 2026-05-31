import os
import time
import boto3
from botocore.exceptions import ClientError

# Read variables injected dynamically by Terraform
STREAM_NAME = os.environ.get('STREAM_NAME', 'FHD_Security_Camera_Stream')
S3_BUCKET = os.environ.get('S3_BUCKET_NAME')

kvs_client = boto3.client('kinesisvideo')
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    if not S3_BUCKET:
        print("Error: S3_BUCKET_NAME environment variable is missing.")
        return {"status": "ERROR", "message": "Missing S3 configuration"}

    print(f"Archiving stream data payload: '{STREAM_NAME}' to bucket: '{S3_BUCKET}'")

    try:
        # 1. Fetch data endpoint plane
        endpoint_response = kvs_client.get_data_endpoint(
            StreamName=STREAM_NAME,
            APIName='GET_MEDIA'
        )
        data_endpoint = endpoint_response['DataEndpoint']
        
        # 2. Target custom endpoint client
        kvs_media_client = boto3.client(
            'kinesis-video-media', 
            endpoint_url=data_endpoint
        )
        
        # 3. Pull fragments
        media_response = kvs_media_client.get_media(
            StreamName=STREAM_NAME,
            StartSelector={'StartSelectorType': 'NOW'}
        )
        
        stream_payload = media_response['Payload']
        timestamp = int(time.time())
        s3_key = f"video-archives/{STREAM_NAME}/{timestamp}-{context.aws_request_id}.mkv"
        
        # 4. Stream 15MB buffered data blocks onto S3 structure
        chunk_data = stream_payload.read(1024 * 1024 * 15) 
        
        if not chunk_data:
            print("Received empty video buffer block.")
            return {"status": "NO_DATA"}

        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=chunk_data,
            ContentType='video/x-matroska'
        )
        
        print(f"Segment chunk committed successfully to S3.")
        return {"status": "SUCCESS", "destination": f"s3://{S3_BUCKET}/{s3_key}"}

    except ClientError as e:
        print(f"AWS Execution Fault: {e.response['Error']['Message']}")
        raise e