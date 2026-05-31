import cv2
import boto3
import time
from io import BytesIO
from botocore.exceptions import ClientError

# --- CONFIGURATION ---
S3_BUCKET_NAME = "minipc-iot-simulation-255945442255"
REGION_NAME = "ap-southeast-1"  # Singapore region
UPLOAD_INTERVAL = 3              # Take a picture and stream to S3 every 3 seconds

def start_monitored_s3_pipeline():
    print(f"📡 Initializing AWS S3 Client for region: {REGION_NAME}...")
    s3_client = boto3.client('s3', region_name=REGION_NAME)
    
    try:
        s3_client.head_bucket(Bucket=S3_BUCKET_NAME)
        print(f"✅ S3 Bucket verified accessible: s3://{S3_BUCKET_NAME}")
    except ClientError as e:
        print(f"❌ [CRITICAL] Cannot access S3 bucket: {e}")
        return

    # Index 0 is your Integrated Camera. Change to 1 or 2 for external USB cameras.
    target_index = 1 
    print(f"🔌 Powering on camera hardware at Index [{target_index}] via DirectShow...")
    cap = cv2.VideoCapture(target_index, cv2.CAP_DSHOW)
    
    if not cap.isOpened():
        print("⚠️ Index 0 failed. Attempting fallback selector [-1]...")
        cap = cv2.VideoCapture(-1, cv2.CAP_DSHOW)

    if not cap.isOpened():
        print("❌ [CRITICAL] Windows OS blocked hardware hook interface entirely.")
        return
        
    # Force camera properties
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    
    # 🔥 FIX 1: CAMERA WARMUP LOOP
    # Flush the first 15-30 raw frames to give the webcam hardware time to stabilize its auto-exposure.
    print("⏳ Warming up camera lens and stabilizing auto-exposure matrix...")
    for _ in range(20):
        cap.read()
        time.sleep(0.05)
    
    print(f"\n🚀 Delivery Pipeline & Monitor GUI Active!")
    print(f"📺 Displaying live view window on monitor.")
    print(f"📸 Uploading frame to S3 every {UPLOAD_INTERVAL} seconds...")
    print("🛑 Press 'q' inside the video window or Ctrl+C in terminal to exit safely.\n")
    
    last_upload_time = 0

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print("⚠️ Hardware warning: Camera frame missed. Retrying...")
                time.sleep(0.05)
                continue
                
            # 🔥 FIX 2: MONITOR DISPLAY WINDOW
            # Render the active numpy matrix array into a native Windows GUI window wrapper
            cv2.imshow("Live Video Stream Monitor", frame)
            
            # 🔥 FIX 3: REPAINT EVENT PUMP
            # This is mandatory. Without waitKey, the monitor window will freeze or stay blank.
            # Pressing 'q' inside the monitor window will gracefully kill the script.
            if cv2.waitKey(1) & 0xFF == ord('q'):
                print("\n[SHUTDOWN] Close request received via Monitor UI Window.")
                break
            
            # Check if it is time to capture a frame for S3 based on your interval physics
            current_time = time.time()
            if current_time - last_upload_time >= UPLOAD_INTERVAL:
                
                # Compress the non-blank image into JPEG binary formatting inside system RAM
                success, encoded_image = cv2.imencode('.jpg', frame)
                if success:
                    image_bytes = BytesIO(encoded_image.tobytes())
                    file_name = f"camera_feeds/frame_{int(current_time)}.jpg"
                    
                    try:
                        # Upload object straight to your S3 bucket target location
                        s3_client.upload_fileobj(
                            image_bytes, 
                            S3_BUCKET_NAME, 
                            file_name,
                            ExtraArgs={'ContentType': 'image/jpeg'}
                        )
                        print(f"📤 [S3 UPLOAD SUCCESS] Saved object: {file_name}")
                        last_upload_time = current_time
                    except Exception as upload_error:
                        print(f"⚠️ Network Upload Error: {upload_error}")

    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Interrupted by user via terminal.")
    finally:
        print("[HARDWARE] Releasing camera device lock...")
        cap.release()
        print("[GUI] Terminating display monitor windows...")
        cv2.destroyAllWindows()
        print("[SHUTDOWN] Clean exit finished.")

if __name__ == "__main__":
    start_monitored_s3_pipeline()
