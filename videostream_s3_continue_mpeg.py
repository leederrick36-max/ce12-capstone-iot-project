import os
import time
import cv2
import boto3

# --- CONFIGURATION ---
S3_BUCKET_NAME = "minipc-iot-simulation-255945442255"
AWS_REGION = "ap-southeast-1"
CHUNK_DURATION_SEC = 10  
FRAME_WIDTH = 640
FRAME_HEIGHT = 480
FPS = 30

def start_playable_s3_stream():
    print(f"📡 Initializing S3 Client Engine...")
    s3_client = boto3.client('s3', region_name=AWS_REGION)
    
    target_index = 1
    cap = cv2.VideoCapture(target_index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(-1, cv2.CAP_DSHOW)
    if not cap.isOpened():
        print("❌ [CRITICAL] Windows OS blocked hardware camera access.")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, FPS)

    print("\n🚀 Standard Video Playback Pipeline Active!")
    print(f"📺 Compiling standard playable .avi files every {CHUNK_DURATION_SEC}s.")
    print("🛑 Press 'q' inside the video window to exit.\n")

    chunk_start_time = time.time()
    chunk_counter = 1
    
    # Define a temporary local filename
    temp_local_file = "temp_output.avi"
    
    # Use MJPEG codec for standard video container writing
    fourcc = cv2.VideoWriter_fourcc(*'MJPG')
    video_writer = cv2.VideoWriter(temp_local_file, fourcc, FPS, (FRAME_WIDTH, FRAME_HEIGHT))

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                continue
                
            cv2.imshow("Live S3 Playable Video Monitor", frame)
            
            # Write frames into the actual local media file structure
            video_writer.write(frame)
            
            current_time = time.time()
            if current_time - chunk_start_time >= CHUNK_DURATION_SEC:
                # Close the local file writer to finalize headers (.avi container indexing)
                video_writer.release()
                
                timestamp = int(current_time)
                s3_file_name = f"video_streams/clip_{chunk_counter:04d}_{timestamp}.avi"
                
                try:
                    # Upload the standard playable media file directly to S3
                    s3_client.upload_file(temp_local_file, S3_BUCKET_NAME, s3_file_name)
                    print(f"📤 [STREAM SUCCESS] Uploaded standard playable clip ──► {s3_file_name}")
                except Exception as upload_err:
                    print(f"⚠️ Upload Error: {upload_err}")
                
                # Forcefully remove the temporary file from your local hard drive
                if os.path.exists(temp_local_file):
                    os.remove(temp_local_file)
                
                # Re-initialize the video writer to begin the next chunk file
                video_writer = cv2.VideoWriter(temp_local_file, fourcc, FPS, (FRAME_WIDTH, FRAME_HEIGHT))
                chunk_start_time = time.time()
                chunk_counter += 1

            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Interrupted by user.")
    finally:
        video_writer.release()
        cap.release()
        cv2.destroyAllWindows()
        if os.path.exists(temp_local_file):
            try:
                os.remove(temp_local_file)
            except:
                pass
        print("[SHUTDOWN] Clean exit finished.")

if __name__ == "__main__":
    start_playable_s3_stream()