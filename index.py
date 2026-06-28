import time
import json
import uuid
import boto3
from datetime import datetime

# Initialize the AWS IoT SiteWise Client globally for connection reuse across executions
sitewise_client = boto3.client('iotsitewise', region_name='ap-southeast-1')

def get_infrastructure_properties(sensor_id=None):
    """
    Looks up the asset model and physical asset twin instance in AWS IoT SiteWise.
    Resolves the specific property UUIDs for the video stream and individual temperature sensors.
    """
    model_name = "MiniPC_Industrial_Gateway_Model"
    asset_name = "MiniPC_Unit_001"
    
    # 1. Identify deployed Asset Model Blueprint
    model_id = None
    models_pager = sitewise_client.get_paginator('list_asset_models')
    for page in models_pager.paginate():
        for model in page['assetModelSummaries']:
            if model['name'] == model_name:
                model_id = model['id']
                break
        if model_id: 
            break
                
    if not model_id:
        print("[ERROR] Asset Model missing. Ensure it is deployed via Terraform first.")
        return None, None, None
    
    # 2. Identify deployed Physical Asset Twin Instance
    asset_id = None
    assets_pager = sitewise_client.get_paginator('list_assets')
    for page in assets_pager.paginate(filter='TOP_LEVEL'):
        for asset in page['assetSummaries']:
            if asset['name'] == asset_name:
                asset_id = asset['id']
                break
        if asset_id: 
            break
                
    if not asset_id:
        print("[ERROR] Asset Twin instance 'MiniPC_Unit_001' missing. Ensure it is deployed via Terraform.")
        return None, None, None
        
    # 3. Resolve the exact Property Channel matching this incoming request
    temp_property_id = None
    video_property_id = None
    target_temp_name = f"Temperature_Sensor_{sensor_id}" if sensor_id is not None else "Temperature"
    
    model_desc = sitewise_client.describe_asset_model(assetModelId=model_id)
    for prop in model_desc.get('assetModelProperties', []):
        if prop['name'] == target_temp_name:
            temp_property_id = prop['id']
        elif prop['name'] == 'LatestVideoClipUrl':
            video_property_id = prop['id']
            
    if not temp_property_id and sensor_id is not None:
        print(f"[WARN] Property slot '{target_temp_name}' not pre-defined inside the model blueprint.")
                
    return asset_id, temp_property_id, video_property_id

def lambda_handler(event, context):
    s3_client = boto3.client('s3')

    # Process all incoming records inside the S3 event batch
    for record in event['Records']:
        bucket_name = record['s3']['bucket']['name']
        file_key = record['s3']['object']['key']
        
        # Calculate a safe fallback timestamp from the S3 event arrival window if payload has anomalies
        event_time_str = record.get('eventTime', '').replace('Z', '+00:00')
        try:
            fallback_timestamp = int(datetime.fromisoformat(event_time_str).timestamp())
        except Exception:
            fallback_timestamp = int(time.time())
            
        lower_key = file_key.lower()
        
        # =========================================================================
        # BRANCH A: ROUTE INCOMING VIDEO CLIP UPLOADS (.mp4, .avi, .mov, etc.)
        # =========================================================================
        if any(lower_key.endswith(ext) for ext in ['.mp4', '.avi', '.mov', '.mkv', '.webm']):
            resolved_asset_id, _, video_prop_id = get_infrastructure_properties(sensor_id=None)

            # Presigned GET url instead of a plain (unsigned) S3 link. The bucket is
            # private (BucketOwnerEnforced + default Block Public Access), so a bare
            # https://bucket.s3.../key URL 403s for anyone without their own AWS
            # credentials. NOTE: this signs with the Lambda's own execution-role
            # (temporary/STS) credentials, so AWS caps the URL's real validity at
            # ~1 hour no matter what ExpiresIn says - that's fine here since a new
            # clip (and a fresh URL) overwrites LatestVideoClipUrl every chunk
            # interval, well under an hour. No IAM change needed: pipeline_role
            # already has s3:GetObject on the whole bucket (sitewise.tf).
            try:
                video_url = s3_client.generate_presigned_url(
                    'get_object',
                    Params={'Bucket': bucket_name, 'Key': file_key},
                    ExpiresIn=3600,
                )
            except Exception as e:
                print(f"[ERROR] Failed generating presigned URL for {file_key}: {str(e)}")
                continue

            if video_prop_id and resolved_asset_id:
                try:
                    sitewise_client.batch_put_asset_property_value(entries=[{
                        'entryId': str(uuid.uuid4()),
                        'assetId': resolved_asset_id,
                        'propertyId': video_prop_id,
                        'propertyValues': [{
                            'value': {'stringValue': video_url}, 
                            'timestamp': {'timeInSeconds': fallback_timestamp, 'offsetInNanos': 0}, 
                            'quality': 'GOOD'
                        }]
                    }])
                    print(f"[SUCCESS] Linked video stream metadata clip: {video_url}")
                except Exception as e:
                    print(f"[ERROR] Failed writing video clip link to SiteWise: {str(e)}")
            continue

        # =========================================================================
        # BRANCH B: ROUTE INCOMING TELEMETRY TEMPERATURE JSON PAYLOADS
        # =========================================================================
        try:
            # Download and parse the single-sensor JSON file from S3
            response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
            raw_body = response['Body'].read().decode('utf-8')
            payload = json.loads(raw_body)
            
            sensor_id = payload.get('sensor_id')
            raw_ts = payload.get('timestamp', fallback_timestamp)
            temp_val = payload.get('temp')
            
            if temp_val is not None:
                # Find the properties allocated specifically for this sensor ID
                resolved_asset_id, temp_prop_id, _ = get_infrastructure_properties(sensor_id=sensor_id)
                
                if temp_prop_id and resolved_asset_id:
                    # Convert device timestamp dynamically (Supports seconds or milliseconds formats)
                    ts_sec = int(raw_ts / 1000) if raw_ts > 9999999999 else int(raw_ts)
                    ts_nano = int(raw_ts % 1000) * 1000000 if raw_ts > 9999999999 else 0
                    
                    # Push telemetry to SiteWise via the highly concurrent data plane API
                    sitewise_client.batch_put_asset_property_value(entries=[{
                        'entryId': str(uuid.uuid4()),
                        'assetId': resolved_asset_id,
                        'propertyId': temp_prop_id,
                        'propertyValues': [{
                            'value': {'doubleValue': float(temp_val)}, 
                            'timestamp': {'timeInSeconds': ts_sec, 'offsetInNanos': ts_nano}, 
                            'quality': 'GOOD'
                        }]
                    }])
                    print(f"[SUCCESS] Ingested Sensor {sensor_id} temperature ({temp_val}°C) to isolated timeline slot.")
                else:
                    print(f"[ERROR] Ingestion skipped. Could not map property for Sensor ID: {sensor_id}")
        except Exception as e:
            print(f"[ERROR] Failed processing payload file '{file_key}': {str(e)}")
            