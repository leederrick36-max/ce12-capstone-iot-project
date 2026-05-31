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
TARGET_INDEX = 1 # 0 = Integrated Camera, 1/2 = External USB Webcams


# 🎬 FILE FORMAT SELECTOR SWITCH 
# Options: "MP4" (Web viewable) | "MKV" (Crash resilient) | "AVI" (Native Windows stability)
CHOSEN_FORMAT = "MKV" 

# Dynamic container mapping engine
if CHOSEN_FORMAT == "MP4":
    FILE_EXTENSION = ".mp4"
    FOURCC_CODEC = cv2.VideoWriter_fourcc(*'mp4v')  # Highly stable generic MPEG-4 on Windows
    CONTENT_TYPE = 'video/mp4'
elif CHOSEN_FORMAT == "MKV":
    FILE_EXTENSION = ".mkv"
    FOURCC_CODEC = cv2.VideoWriter_fourcc(*'XVID')  # Linear streaming block encoding
    CONTENT_TYPE = 'video/x-matroska'
elif CHOSEN_FORMAT == "AVI":
    FILE_EXTENSION = ".avi"
    FOURCC_CODEC = cv2.VideoWriter_fourcc(*'MJPG')  # High speed Motion-JPEG container format
    CONTENT_TYPE = 'video/x-msvideo'
else:
    raise ValueError("Invalid format chosen. Please use 'MP4', 'MKV', or 'AVI'.")


def start_standardized_s3_stream():
    print(f"📡 Initializing S3 Client Engine for region: {AWS_REGION}...")
    s3_client = boto3.client('s3', region_name=AWS_REGION)
    
    # Target camera hardware index (0 = Integrated Lens, 1/2 = External USB Webcams)
    target_index = TARGET_INDEX
    print(f"🔌 Powering on webcam hardware at Index [{target_index}] via DirectShow...")
    cap = cv2.VideoCapture(target_index, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(-1, cv2.CAP_DSHOW)
    if not cap.isOpened():
        print("❌ [CRITICAL] Windows OS blocked hardware camera access.")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, FPS)

    # Temporary holding file on local disk before streaming it over HTTPS
    temp_local_file = f"temp_output{FILE_EXTENSION}"

    print(f"\n🚀 Standard Video Playback Pipeline Active!")
    print(f"📺 Compiling standard playable {FILE_EXTENSION} files every {CHUNK_DURATION_SEC}s.")
    print("🛑 Press 'q' inside the video window or Ctrl+C in terminal to exit.\n")

    chunk_start_time = time.time()
    chunk_counter = 1
    
    # Initialize the specific local storage container writing handle
    video_writer = cv2.VideoWriter(temp_local_file, FOURCC_CODEC, FPS, (FRAME_WIDTH, FRAME_HEIGHT))

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                continue
                
            # Render the stream locally on your monitor
            cv2.imshow("Live S3 Playable Video Monitor", frame)
            
            # Write frames into the structured temporary video stream file on disk
            video_writer.write(frame)
            
            current_time = time.time()
            if current_time - chunk_start_time >= CHUNK_DURATION_SEC:
                # Close the writer handles to safely write index tables and trailer footprints
                video_writer.release()
                
                timestamp = int(current_time)
                s3_file_name = f"video_streams/clip_{chunk_counter:04d}_{timestamp}{FILE_EXTENSION}"
                
                try:
                    # Upload the completed container block directly to S3
                    s3_client.upload_file(
                        temp_local_file, 
                        S3_BUCKET_NAME, 
                        s3_file_name,
                        ExtraArgs={'ContentType': CONTENT_TYPE}
                    )
                    print(f"📤 [STREAM SUCCESS] Uploaded standard {FILE_EXTENSION} clip ──► {s3_file_name}")
                except Exception as upload_err:
                    print(f"⚠️ Upload Error: {upload_err}")
                
                # Delete local temp chunk file immediately to keep local storage clean
                if os.path.exists(temp_local_file):
                    os.remove(temp_local_file)
                
                # Re-open a fresh file handle to construct the next clip chunk
                video_writer = cv2.VideoWriter(temp_local_file, FOURCC_CODEC, FPS, (FRAME_WIDTH, FRAME_HEIGHT))
                chunk_start_time = time.time()
                chunk_counter += 1

            # Monitor event handler window: press 'q' to stop streaming safely
            if cv2.waitKey(1) & 0xFF == ord('q'):
                print("\n[SHUTDOWN] Close requested via Monitor GUI.")
                break

    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Interrupted by user via terminal.")
    finally:
        # Final safety cleanup tracking routines
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
    start_standardized_s3_stream()