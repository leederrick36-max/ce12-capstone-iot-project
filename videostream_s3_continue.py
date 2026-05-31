import os
import time
import cv2
import boto3
from io import BytesIO

# --- CONFIGURATION ---
S3_BUCKET_NAME = "minipc-iot-simulation-255945442255"
AWS_REGION = "ap-southeast-1"
# The script will bundle frames and stream them to S3 every X seconds
CHUNK_DURATION_SEC = 10  

FRAME_WIDTH = 640
FRAME_HEIGHT = 480
FPS = 30

def start_s3_multipart_stream():
    print(f"📡 Initializing S3 Client Engine for region: {AWS_REGION}...")
    s3_client = boto3.client('s3', region_name=AWS_REGION)
    
    # Target camera index (0 = Integrated Camera, 1 or 2 = External USB Webcams)
    target_index = 1
    print(f"🔌 Powering on webcam hardware at Index [{target_index}] via DirectShow...")
    cap = cv2.VideoCapture(target_index, cv2.CAP_DSHOW)
    
    if not cap.isOpened():
        print("⚠️ Index 0 busy. Attempting fallback Windows selector [-1]...")
        cap = cv2.VideoCapture(-1, cv2.CAP_DSHOW)
        
    if not cap.isOpened():
        print("❌ [CRITICAL] Windows OS blocked hardware camera access.")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, FPS)

    print("\n🚀 Pure Python S3 Streaming Pipeline Active!")
    print(f"📺 Live Monitor window opened. Video slices are uploading every {CHUNK_DURATION_SEC}s.")
    print("🛑 Press 'q' inside the video window or Ctrl+C in terminal to exit.\n")

    # Tracking states for our RAM memory buffer
    chunk_start_time = time.time()
    chunk_counter = 1
    
    # This list acts as our virtual video file in system RAM
    frame_buffer = []

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                time.sleep(0.01)
                continue
                
            # 1. Show the live feed on your physical monitor smoothly
            cv2.imshow("Live S3 Stream Infrastructure Monitor", frame)
            
            # 2. Compress the active frame to JPEG bytes and save it into our RAM list
            success, encoded_frame = cv2.imencode('.jpg', frame)
            if success:
                frame_buffer.append(encoded_frame.tobytes())
            
            # 3. Check if our video fragment chunk has reached its time boundary limit
            current_time = time.time()
            if current_time - chunk_start_time >= CHUNK_DURATION_SEC:
                
                if len(frame_buffer) > 0:
                    # Format a clear, chronologically ordered file name template
                    timestamp = int(current_time)
                    file_name = f"video_streams/chunk_{chunk_counter:04d}_{timestamp}.bin"
                    
                    # Flatten our list of frame bytes into one continuous byte sequence block
                    raw_video_stream_bytes = b"".join(frame_buffer)
                    
                    try:
                        # Wrap the bytes and stream them directly over an HTTPS connection to S3
                        s3_client.put_object(
                            Bucket=S3_BUCKET_NAME,
                            Key=file_name,
                            Body=raw_video_stream_bytes,
                            ContentType='application/octet-stream'
                        )
                        print(f"📤 [STREAM SUCCESS] Uploaded {len(raw_video_stream_bytes)/1024/1024:.2f} MB frame sequence ──► {file_name}")
                    except Exception as upload_err:
                        print(f"⚠️ Network Upload Latency Drop: {upload_err}")
                
                # Reset buffers completely to start recording the next continuous segment
                frame_buffer = []
                chunk_start_time = time.time()
                chunk_counter += 1

            # Monitor event handler: press 'q' on the image panel window to quit gracefully
            if cv2.waitKey(1) & 0xFF == ord('q'):
                print("\n[SHUTDOWN] Close requested via Monitor GUI.")
                break

    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Interrupted by user via terminal execution.")
    finally:
        print("[SHUTDOWN] Cleaning up memory buffers and hardware interfaces...")
        cap.release()
        cv2.destroyAllWindows()
        print("[SHUTDOWN] Clean exit finished.")

if __name__ == "__main__":
    start_s3_multipart_stream()