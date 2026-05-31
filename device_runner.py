import os
import sys
import time
import json
import random
import threading
import cv2
import boto3
from awscrt import mqtt
from awsiot import mqtt_connection_builder

# ==============================================================================
# --- 1. GLOBAL INTEGRATED CONFIGURATION ---------------------------------------
# ==============================================================================
# AWS IoT Core Parameters
ENDPOINT = "a19iwwhi2w6u01-ats.iot.ap-southeast-1.amazonaws.com"
CREDENTIAL_ENDPOINT = "c3v9qpts8gxznh.credentials.iot.ap-southeast-1.amazonaws.com"
TEMPLATE_NAME = "MiniPC_Fleet_Template"
ROLE_ALIAS = "KvsCameraRoleAlias"
SERIAL_NUMBER = "MPC-SN-001"

# AWS S3 Video Parameters
S3_BUCKET_NAME = "minipc-iot-simulation-255945442255"
AWS_REGION = "ap-southeast-1"
CHUNK_DURATION_SEC = 10  
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
FPS = 30
TARGET_INDEX = 1  # 0 = Integrated Camera, 1/2 = External USB Webcams

# Local Security Credential Paths (Windows Format)
CLAIM_CERT = "claim.cert.pem"
CLAIM_KEY = "claim.private.key"
ROOT_CA = "AmazonRootCA1.pem"
PERM_CERT = "perm.cert.pem"
PERM_KEY = "perm.private.key"

# Video Container Mapping Configuration
CHOSEN_FORMAT = "MKV"  # Options: "MP4" | "MKV" | "AVI"
if CHOSEN_FORMAT == "MP4":
    FILE_EXTENSION = ".mp4"
    FOURCC_CODEC = cv2.VideoWriter_fourcc(*'mp4v')
    CONTENT_TYPE = 'video/mp4'
elif CHOSEN_FORMAT == "MKV":
    FILE_EXTENSION = ".mkv"
    FOURCC_CODEC = cv2.VideoWriter_fourcc(*'XVID')
    CONTENT_TYPE = 'video/x-matroska'
elif CHOSEN_FORMAT == "AVI":
    FILE_EXTENSION = ".avi"
    FOURCC_CODEC = cv2.VideoWriter_fourcc(*'MJPG')
    CONTENT_TYPE = 'video/x-msvideo'
else:
    raise ValueError("Invalid video format chosen.")

# Thread Communication Safe Shared Frame State
frame_lock = threading.Lock()
latest_shared_frame = None
system_running = True


# ==============================================================================
# --- 2. FLEET PROVISIONING INTERFACES -----------------------------------------
# ==============================================================================
class ProvisioningHandler:
    def __init__(self):
        self.finished = False
        self.mqtt_connection = None

    def on_create_keys_success(self, response_payload):
        print("[PROVISION] Keys received. Writing to disk...")
        certificate_pem = response_payload.get("certificatePem")
        private_key = response_payload.get("privateKey")
        ownership_token = response_payload.get("certificateOwnershipToken")

        with open(PERM_CERT, "w") as f: 
            f.write(certificate_pem)
        with open(PERM_KEY, "w") as f: 
            f.write(private_key)
        
        register_payload = {
            "certificateOwnershipToken": ownership_token,
            "parameters": {"SerialNumber": SERIAL_NUMBER}
        }
        
        print("[PROVISION] Registering device with provisioning template...")
        self.mqtt_connection.publish(
            topic=f"$aws/provisioning-templates/{TEMPLATE_NAME}/provision/json",
            payload=json.dumps(register_payload),
            qos=mqtt.QoS.AT_LEAST_ONCE
        )

    def on_create_keys_rejected(self, payload):
        print(f"\n[ERROR] Certificate creation rejected by AWS IoT: {payload}")
        self.finished = True

    def on_register_success(self, payload):
        print("[SUCCESS] Device registered in AWS IoT Registry.")
        self.finished = True

    def on_register_rejected(self, payload):
        print(f"\n[ERROR] Device registration rejected by AWS IoT: {payload}")
        self.finished = True


def run_provisioning():
    print("[FORCE] Starting Fleet Provisioning workflow...")
    handler = ProvisioningHandler()
    
    handler.mqtt_connection = mqtt_connection_builder.mtls_from_path(
        endpoint=ENDPOINT, 
        cert_filepath=CLAIM_CERT, 
        pri_key_filepath=CLAIM_KEY,
        ca_filepath=ROOT_CA, 
        client_id=f"provisioning-{SERIAL_NUMBER}"
    )
    handler.mqtt_connection.connect().result()
    
    handler.mqtt_connection.subscribe(
        topic="$aws/certificates/create/json/accepted", 
        qos=mqtt.QoS.AT_LEAST_ONCE,
        callback=lambda topic, payload, **kwargs: handler.on_create_keys_success(json.loads(payload))
    )
    handler.mqtt_connection.subscribe(
        topic=f"$aws/provisioning-templates/{TEMPLATE_NAME}/provision/json/accepted", 
        qos=mqtt.QoS.AT_LEAST_ONCE,
        callback=lambda topic, payload, **kwargs: handler.on_register_success(json.loads(payload))
    )
    handler.mqtt_connection.subscribe(
        topic="$aws/certificates/create/json/rejected", 
        qos=mqtt.QoS.AT_LEAST_ONCE,
        callback=lambda topic, payload, **kwargs: handler.on_create_keys_rejected(json.loads(payload))
    )
    handler.mqtt_connection.subscribe(
        topic=f"$aws/provisioning-templates/{TEMPLATE_NAME}/provision/json/rejected", 
        qos=mqtt.QoS.AT_LEAST_ONCE,
        callback=lambda topic, payload, **kwargs: handler.on_register_rejected(json.loads(payload))
    )
    
    handler.mqtt_connection.publish(
        topic="$aws/certificates/create/json", \
        payload="{}", \
        qos=mqtt.QoS.AT_LEAST_ONCE
    )
    
    while not handler.finished:
        time.sleep(1)
        
    handler.mqtt_connection.disconnect().result()


# ==============================================================================
# --- THREAD A: TELEMETRY ROUTINE (AWS IoT CORE) -------------------------------
# ==============================================================================
def telemetry_thread_worker():
    """Establishes long-lived MQTT connectivity to publish sensor statistics."""
    global system_running
    print(f"[TELEMETRY] Initiating active session context tracking as: {SERIAL_NUMBER}...")
    
    try:
        active_conn = mqtt_connection_builder.mtls_from_path(
            endpoint=ENDPOINT, 
            cert_filepath=PERM_CERT, 
            pri_key_filepath=PERM_KEY,
            ca_filepath=ROOT_CA, 
            client_id=SERIAL_NUMBER
        )
        active_conn.connect().result()
        print("[TELEMETRY] Secure tunnel communication path online.")
        
        while system_running:
            print(f"\n--- Batch Dispatch Event: {time.strftime('%X')} ---")
            for i in range(1, 11):
                if not system_running:
                    break
                topic = f"fleet/sensors/{i}"
                payload = {
                    "sensor_id": i,
                    "timestamp": int(time.time()),
                    "temp": round(random.uniform(22.0, 30.0), 2),
                    "status": "online"
                }
                print(f"[SEND] {topic} -> data: {payload}")
                active_conn.publish(
                    topic=topic, 
                    payload=json.dumps(payload), 
                    qos=mqtt.QoS.AT_LEAST_ONCE
                )
            
            # Subdivided sleep intervals allow fast exit checks on shutdown
            for _ in range(30):
                if not system_running:
                    break
                time.sleep(1)
                
    except Exception as e:
        print(f"[TELEMETRY CRITICAL ERROR]: {e}")


# ==============================================================================
# --- THREAD B: MEDIA ROUTINE (AWS S3 VIDEO STREAM) ----------------------------
# ==============================================================================
def video_thread_worker():
    """Captures camera hardware blocks, saves to disk, and pushes segments to S3."""
    global latest_shared_frame, system_running
    print(f"[VIDEO] Initializing S3 Client Engine for region: {AWS_REGION}...")
    s3_client = boto3.client('s3', region_name=AWS_REGION)
    
    print(f"[VIDEO] Powering on webcam hardware at Index [{TARGET_INDEX}] via DirectShow...")
    cap = cv2.VideoCapture(TARGET_INDEX, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(-1, cv2.CAP_DSHOW)
    if not cap.isOpened():
        print("❌ [VIDEO CRITICAL] Windows OS blocked hardware camera access.")
        system_running = False
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, FPS)

    temp_local_file = f"temp_output{FILE_EXTENSION}"
    chunk_start_time = time.time()
    chunk_counter = 1
    
    video_writer = cv2.VideoWriter(temp_local_file, FOURCC_CODEC, FPS, (FRAME_WIDTH, FRAME_HEIGHT))
    print(f"[VIDEO] Media stream engine compiling {FILE_EXTENSION} file blocks every {CHUNK_DURATION_SEC}s.")

    try:
        while system_running:
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.01)
                continue
                
            # Safely pass the frame to the main thread for rendering
            with frame_lock:
                latest_shared_frame = frame.copy()
                
            video_writer.write(frame)
            
            current_time = time.time()
            if current_time - chunk_start_time >= CHUNK_DURATION_SEC:
                video_writer.release()
                
                timestamp = int(current_time)
                s3_file_name = f"video_streams/clip_{chunk_counter:04d}_{timestamp}{FILE_EXTENSION}"
                
                try:
                    s3_client.upload_file(
                        temp_local_file, 
                        S3_BUCKET_NAME, 
                        s3_file_name,
                        ExtraArgs={'ContentType': CONTENT_TYPE}
                    )
                    print(f"📤 [STREAM SUCCESS] Uploaded standard {FILE_EXTENSION} clip ──► {s3_file_name}")
                except Exception as upload_err:
                    print(f"⚠️ [VIDEO ERROR] Upload failed: {upload_err}")
                
                if os.path.exists(temp_local_file):
                    try:
                        os.remove(temp_local_file)
                    except:
                        pass
                
                video_writer = cv2.VideoWriter(temp_local_file, FOURCC_CODEC, FPS, (FRAME_WIDTH, FRAME_HEIGHT))
                chunk_start_time = time.time()
                chunk_counter += 1

    except Exception as e:
        print(f"[VIDEO CRITICAL ERROR]: {e}")
    finally:
        video_writer.release()
        cap.release()
        if os.path.exists(temp_local_file):
            try:
                os.remove(temp_local_file)
            except:
                pass


# ==============================================================================
# --- 3. MAIN SERVICE MAIN THREAD (GUI RENDER ENGINE) --------------------------
# ==============================================================================
def main():
    global latest_shared_frame, system_running
    print("====== STARTING WINDOWS 11 MULTI-THREADED IOT AGENT ======")
    
    # 1. Verification Phase for AWS Fleet Provisioning Onboarding 
    if not os.path.exists(PERM_CERT) or not os.path.exists(PERM_KEY):
        run_provisioning()
    else:
        print("[INFO] Production authentication profiles present on disk. Skipping onboarding.")

    if not os.path.exists(PERM_CERT) or not os.path.exists(PERM_KEY):
        print("[CRITICAL] Production security profiles missing. Aborting system initiation.")
        sys.exit(1)

    # 2. Spawning Background Thread Workers
    t1_telemetry = threading.Thread(target=telemetry_thread_worker, name="TelemetryThread", daemon=True)
    t2_video = threading.Thread(target=video_thread_worker, name="VideoStreamThread", daemon=True)

    print("[SYSTEM] Launching background telemetry and recording channels...")
    t1_telemetry.start()
    t2_video.start()

    print("\n🚀 Standard Video Playback Pipeline Active!")
    print("🛑 To exit, focus the video window and press 'q', or hit Ctrl+C in your terminal.\n")

    # 3. Main Windows GUI Event Processing Thread Loop
    try:
        while system_running:
            local_render_frame = None
            
            with frame_lock:
                if latest_shared_frame is not None:
                    local_render_frame = latest_shared_frame.copy()
            
            if local_render_frame is not None:
                cv2.imshow("Live S3 Playable Video Monitor", local_render_frame)
            
            # Windows OS requires waitKey to process GUI painting event queues
            if cv2.waitKey(1) & 0xFF == ord('q'):
                print("\n[SHUTDOWN] Close requested via Monitor GUI window.")
                break
                
    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Interrupted by user via terminal.")
        
    # 4. Clean Shutdown Teardown Process
    print("[SHUTDOWN] Terminating system execution loops cleanly...")
    system_running = False
    time.sleep(1) # Give threads a brief window to complete loops
    cv2.destroyAllWindows()
    print("[STOPPED] Closed all active Windows data and video interfaces safely.")

if __name__ == "__main__":
    main()