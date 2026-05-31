This documentation provides a comprehensive, component-by-component architectural overview of the modularized infrastructure.

The configuration establishes a **Secure Fleet Provisioning Pipeline** and a **Real-Time Telemetry & Video Processing Engine** utilizing AWS IoT Core, AWS Kinesis Video Streams *, and Amazon S3.

--* KVS is not used currently. The IOT device will upload the video clips to S3 directly. See README.md(last section) CE12G3-IOT Repo . There is not AWS SDK available currently and unofficial third party libs has to be used instead.

### Architectural Workflow Overview

```
[ Physical IoT Device ]
       │
       ├── (Stage 1: Bootstrap) ──> Connects using temporary Claim Certificate [iot.tf]
       │                            Registers device with Fleet Provisioning Template [iot.tf]
       │
       └── (Stage 2: Operations) ─> Receives unique Permanent Certificate & Thing Identity [iot.tf]
                                    │
                                    ├── [Telemetry MQTT] ──> AWS IoT Topic Rule ──> Saved to Amazon S3 [S3bucket.tf]
                                    │
                                    └── [Video Streaming] ──> Assumes KVS Role ──> Streams to Kinesis Video Stream [kinesis.tf]
                                                                                   └─> Auto-extracts frames/clips to S3 [kinesis.tf]

```

---

### 1. Data Ingestion & Storage Component (`data.tf` & `S3bucket.tf`)

This layer establishes the physical storage layout (the Data Lake) and the programmatic metadata hooks needed to run environmental multi-tenant dynamic calculations across the resources.

#### Data Discovery Data Blocks (`data.tf`)

* 
**`data.aws_caller_identity.current`**: Queries the AWS security context to obtain the deployment account ID dynamically. Used to create unique global naming conventions without hardcoding accounts.


* 
**`data.aws_region.current`**: Retrieves the target AWS deployment region (e.g., `ap-southeast-1`) at runtime.


* 
**`data.aws_iot_endpoint.data` & `data.aws_iot_endpoint.creds**`: Queries AWS IoT Core automatically for account-specific endpoints. `data` returns the ATS-isolated MQTT endpoint for telemetry routing, while `creds` returns the endpoint for the operational role credential provider.



#### Storage Resources (`S3bucket.tf`)

* 
**`aws_s3_bucket.simulation_data`**: Deploys the main storage bucket named `minipc-iot-simulation-<Account-ID>`. The property `force_destroy = true` ensures that when tearing down the environment, Terraform clears out stored media files and objects automatically without hanging up.


* 
**`aws_s3_bucket_ownership_controls.simulation_data_controls`**: Enforces the `BucketOwnerEnforced` rule. This explicitly disables traditional S3 Access Control Lists (ACLs), ensuring all data within the bucket relies entirely on IAM and bucket-level security policies.


* 
**`aws_s3_bucket_policy.allow_kvs_write`**: Evaluates security parameters to grant write authority to the native AWS Service Principal `kinesisvideo.amazonaws.com`. This allows Kinesis Video Streams to stream snapshots and media blocks directly into the destination bucket path safely.



---

### 2. Device Identity & Onboarding Engine (`iot.tf`)

This component maps out an enterprise-grade **Fleet Provisioning Bootstrap Workflow**, managing the transformation from unverified physical hardware into securely authenticated AWS IoT assets.

#### The First-Boot Identity (The "Claim")

* 
**`tls_private_key.claim_key`**: Compiles an in-memory 2048-bit RSA private key.


* 
**`tls_self_signed_cert.claim_cert_tls`**: Formulates a self-signed X.509 certificate anchored to the key. It is configured with an active runtime duration of 1 year (`8760` hours) for the explicit use cases of digital signatures and data encipherment.


* 
**`aws_iot_certificate.claim_cert`**: Registers the generated certificate payload directly inside AWS IoT Core and flips its execution status to `active`. This creates the shared "Bootstrap" identity burned onto the fleet hardware at the factory.



#### Bootstrap Security Boundaries

* 
**`aws_iot_policy.claim_policy`**: Employs a strict zero-trust security structure. Physical devices presenting the generic Bootstrap Claim certificate are restricted from interacting with production infrastructure. They can *only* log into MQTT (`iot:Connect`) and interact exclusively with the core system topics required to generate keys (`$aws/certificates/create/*`) and execute onboarding workflows (`$aws/provisioning-templates/...`).


* 
**`aws_iot_policy_attachment.claim_attach`**: Binds the `ProvisioningClaimPolicy` restrictions directly to the bootstrap `claim_cert` instance.



#### Automated Production Lifecycle Engine

* 
**`aws_iam_role.provisioning_role` & `prov_attach**`: Grants the core AWS IoT service engine authority to register cloud identities on the behalf by mapping the managed policy `AWSIoTThingsRegistration`.


* 
**`aws_iot_provisioning_template.fleet_template`**: The functional brain of the automated fleet onboarding pipeline. When an authenticated device passes a unique physical hardware `SerialNumber` via the secure bootstrap topic, this JSON template automatically handles three actions:


1. Registers a brand new physical identity tracking token inside the IoT Registry named `Device_<SerialNumber>`.


2. Spins up and activates a unique, long-lived operational cryptographic certificate.


3. Attaches the `PermanentFleetPolicy` directly to the new device certificate, instantly terminating its temporary bootstrap access rights.





---

### 3. Operational Security & Telemetry Processing (`iot.tf` - Continued)

Once a device finishes onboarding, it uses its permanent credentials to communicate through this secure telemetry architecture.

#### Operational Access Strategy

* 
**`aws_iot_policy.permanent_fleet_policy`**: Controls active operational boundaries. It permits generic ongoing MQTT communication loops (`iot:Connect`, `iot:Publish`, etc.) across production lines. Critically, it explicitly authorizes the physical hardware device to hit the IoT Credential Provider and assume the `KvsCameraRoleAlias` safely via standard X.509 certificates (`iot:AssumeRoleWithCertificate`).



#### Telemetry Route Pipelines

* 
**`aws_iam_role.iot_s3_role` & `iot_s3_policy**`: Creates an execution role that grants AWS IoT Core the cryptographic authority to write sensor data directly into the application's secure S3 data lake bucket.


* 
**`aws_iot_topic_rule.sensor_to_s3`**: Listens continuously to incoming structured messages utilizing the SQL query `SELECT * FROM 'fleet/sensors/+'`. The wildcard (`+`) captures tracking data across individual device feeds in real-time. The incoming JSON data packets are then routed directly into the designated S3 bucket without managing custom middleware. Payloads are structurally organized on disk by topic extraction and generation metrics: `sensor_data/${topic()}/${timestamp()}.json`.



---

### 4. Real-Time Video Ingestion Engine (`kinesis.tf`)

This component handles the secure transmission of high-bandwidth video streams from edge devices and orchestrates automated media archiving.

#### Video Stream Architecture

* 
**`aws_kinesis_video_stream.video_stream`**: Establishes an ingestion pipeline named `FHD_Security_Camera_Stream`. It enforces a sliding 24-hour video frame data retention loop on AWS media SSD shards before aging data out.



#### Token Exchange & Edge Authorizations

* 
**`aws_iam_role.kvs_role`**: An IAM role configured with an execution trust policy allowing the AWS IoT Credential Provider service (`credentials.iot.amazonaws.com`) to assume it. This permits edge devices to exchange their X.509 client certificates for short-lived AWS IAM temporary security tokens.


* 
**`aws_iam_role_policy.kvs_policy`**: Attaches strict boundaries to the KVS token. Devices assuming this role are restricted to video interaction APIs (`kinesisvideo:PutMedia`, `DescribeStream`, `GetDataEndpoint`) mapped precisely against the unique video stream ARN resource.


* 
**`aws_iot_role_alias.kvs_alias`**: Wraps the IAM role into a user-friendly identifier string (`KvsCameraRoleAlias`). This abstract pointer allows the physical hardware code to make role requests without requiring internal AWS account structure details.



#### Automated S3 Media Archiving Pipeline

* 
**`aws_iam_role_policy.kvs_s3_archiving`**: Authorizes the physical device's assumed video role to push objects directly into the S3 bucket data structure.


* 
**`null_resource.enable_kvs_s3_archiving`**: A specialized execution wrapper that solves a limitation in native CloudFormation/Terraform bindings for Kinesis. It creates an explicit lifecycle hook that triggers immediately after the video stream, bucket configuration, and bucket policies are ready.


* 
**`local-exec Provisioner`**: Runs an isolated AWS CLI command on the deployment runner. This overlays configuration settings onto the live streaming engine via the `update-image-generation-configuration` API call. It enables automatic image generation, telling Kinesis Video Streams to process incoming video data, extract frames as standard JPEGs at a continuous interval of every 3000ms (`SamplingInterval`), and store them directly in the designated S3 bucket lake path.



---

### 5. Outputs & Edge Export Assets (`output.tf`)

The final layer extracts key cloud state metrics and outputs the operational files needed to complete device deployment.

* 
**`output.iot_data_endpoint` & `iot_credential_endpoint**`: Returns the precise URLs the physical device applications need to point to for MQTT message routing and IAM security role token exchanges.


* 
**`output.s3_bucket_name`**: Returns the calculated physical name of the S3 storage deployment.


* 
**`local_file.claim_key_file` & `claim_cert_file**`: Takes the bootstrap credentials generated securely in-memory by Terraform and writes them to local project files named `claim.private.key` and `claim.cert.pem`.



> **Operator Note:** These generated bootstrap files represent the core identity assets for the fleet initialization. They should be packaged together and burned onto the physical device hardware at your manufacturing facility to kick off the automated provisioning loop upon first power-on.