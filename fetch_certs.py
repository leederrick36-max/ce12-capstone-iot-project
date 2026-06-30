"""
fetch_certs.py - container startup bootstrap step

Pulls this device's permanent IoT certificate material out of SSM Parameter
Store and writes it to local files, BEFORE device_runner.py starts. This
keeps private key material out of the Docker image entirely (it never gets
baked into a layer) - the container fetches it fresh from AWS on every run.

Assumes the device has already been through Fleet Provisioning once (the
MPC-SN-001 identity already exists in the AWS IoT registry) and this
container is just re-running as that same already-provisioned device, so
only the permanent cert + key + root CA are needed - no claim certificate.

Expects three SecureString parameters in SSM (names overridable via env vars
so the same image can be reused for other devices/serial numbers):
    /minipc/perm_cert  -> perm.cert.pem
    /minipc/perm_key   -> perm.private.key
    /minipc/root_ca    -> AmazonRootCA1.pem

Required IAM permission on the ECS task role:
    ssm:GetParameter on each of the three parameter ARNs above
"""

import os
import sys
import boto3
from botocore.exceptions import ClientError

REGION = os.environ.get("AWS_REGION_NAME", "ap-southeast-1")

PARAMS = {
    os.environ.get("SSM_PERM_CERT_PARAM", "/minipc/perm_cert"): "perm.cert.pem",
    os.environ.get("SSM_PERM_KEY_PARAM", "/minipc/perm_key"): "perm.private.key",
    os.environ.get("SSM_ROOT_CA_PARAM", "/minipc/root_ca"): "AmazonRootCA1.pem",
}


def main():
    ssm = boto3.client("ssm", region_name=REGION)

    for param_name, local_filename in PARAMS.items():
        try:
            response = ssm.get_parameter(Name=param_name, WithDecryption=True)
        except ClientError as e:
            print(f"[BOOTSTRAP CRITICAL] Failed to fetch '{param_name}' from SSM: {e}")
            sys.exit(1)

        with open(local_filename, "w") as f:
            f.write(response["Parameter"]["Value"])
        print(f"[BOOTSTRAP] Wrote {local_filename} from SSM parameter {param_name}.")


if __name__ == "__main__":
    main()
