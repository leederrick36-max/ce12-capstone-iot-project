**Project Overview**
- **Purpose:**: Terraform configuration that provisions an AWS IoT + SiteWise demonstration environment for MiniPC fleet telemetry. It includes IoT provisioning templates, topic rules, S3 routing, SiteWise asset model and asset, and a Lambda-based SiteWise ingestion forwarder.

**Repository Files**
- **backend.tf:**: (optional) backend configuration for Terraform state (if present/configured).
- **provider.tf:**: provider blocks and required provider versions for `aws`, `awscc`, `tls`, and `local`.
- **iot.tf:**: IoT resources including certificates, policies, provisioning template, and topic rules for S3 and lifecycle monitoring.
- **sitewise.tf:**: SiteWise asset model and asset plus the original IoT topic rule that routes telemetry; this file was updated to send SiteWise ingestion via a Lambda action.
- **lambda_sitewise.tf:**: IAM role, inline policy, Lambda resource and `aws_lambda_permission` allowing IoT to invoke the function.
- **sitewise_ingest/handler.py:**: Python Lambda handler that calls `iotsitewise.BatchPutAssetPropertyValue` to write telemetry to SiteWise.
- **sitewise_ingest/build.sh:**: Simple build script to create `sitewise_ingest/sitewise_ingest.zip` for the Lambda function.
- **S3bucket.tf, data.tf, output.tf, README.md:**: Other supporting Terraform files and outputs (see files in repo root).

**What I changed/added**
- **Replaced unsupported `iot_sitewise` action**: The AWS provider did not accept the `iot_site_wise`/`iot_sitewise` action in the IoT rule, so the rule now invokes a Lambda to perform SiteWise writes.
- **Added Lambda forwarder**: `lambda_sitewise.tf` + handler under `sitewise_ingest/` to perform `BatchPutAssetPropertyValue` calls.

**Build & Deploy**
- **Build Lambda zip:** Run the build script to create the deployment artifact.

```bash
cd /home/kuankm/CE12G3-IOT-V3/sitewise_ingest
./build.sh
```

- **Initialize & validate Terraform:**

```bash
cd /home/kuankm/CE12G3-IOT-V3
terraform init
terraform validate
```

- **Plan & apply:**

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

**Notes & Caveats**
- **AWS Credentials:**: Terraform and the Lambda build require valid AWS credentials configured via environment variables, `~/.aws/credentials`, or an assumed role.
- **Region:**: Provider region is set in `provider.tf` (currently `ap-southeast-1`). Change as needed.
- **SiteWise property id:**: The Lambda currently uses the environment variables `ASSET_ID` and `PROPERTY_ID` (populated from the SiteWise asset and model in the Terraform environment). Confirm `PROPERTY_ID` matches the property logical ID / property identifier expected by SiteWise (not the property name).
- **Lambda runtime / sizing:**: The handler is a minimal Python3.11 function with a short timeout (3s). Increase timeout/memory if your SiteWise calls need more time.
- **Logs & debugging:**: Lambda writes to CloudWatch Logs. Use the AWS Console or `aws logs` to troubleshoot runtime errors.

**Useful commands**
- **Show current state and created resources:**

```bash
terraform show
```

- **Destroy resources:**

```bash
terraform destroy
```

**Where to look next**
- Handler improvements: add retries, batch aggregation, and better error handling for `BatchPutAssetPropertyValue` responses.
- Security hardening: narrow IAM permissions for the Lambda to specific SiteWise resources (instead of `*`) once exact ARNs are known.

If you'd like, I can expand this README with architecture diagrams, sample MQTT payloads, or an example end-to-end test script.

**Example MQTT Payload & Quick Test**
- **Sample payload (JSON):**

```json
{
	"temp": 23.7,
	"timestamp": 1717700000
}
```

- **Publish with AWS CLI (uses IoT Data endpoint output):**

Replace `<IOT_DATA_ENDPOINT>` with the value from `terraform output iot_data_endpoint` and run:

```bash
aws iot-data publish \
	--topic "fleet/sensors/001" \
	--payload '{"temp":23.7,"timestamp":1717700000}' \
	--endpoint-url "https://<IOT_DATA_ENDPOINT>" \
	--cli-binary-format raw-in-base64-out
```

- **Publish with mosquitto_pub (TLS cert example):**

If you have device credentials (client cert/key), you can publish with `mosquitto_pub`:

```bash
mosquitto_pub -h <IOT_DATA_ENDPOINT> -p 8883 \
	--cafile AmazonRootCA1.pem \
	--cert device-certificate.pem.crt \
	--key device-private.pem.key \
	-t "fleet/sensors/001" -m '{"temp":23.7,"timestamp":1717700000}'
```

- **Verify ingestion**
	- Check Lambda logs in CloudWatch: `aws logs tail /aws/lambda/sitewise_ingest --follow` to see handler execution and errors.
	- Confirm SiteWise property updates in the AWS SiteWise console for the asset `MiniPC_Unit_001` or by calling the SiteWise Describe/Asset API.

# CE12G3-IOT-V3
AWS Core IOT to AWS SiteWise, take out kinesis. Ready for integration with Grafana
