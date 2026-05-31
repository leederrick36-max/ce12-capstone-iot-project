**Activate VenV**

venv\Scripts\Activate.ps1

**Install libraries**

pip install awsiotsdk  boto3  opencv-python

# Adjust the AWS S3 Video Parameters in the python code

# Ensure that claim.cert.pem and claim.private.key are in the same diectory as device_runner.py. These 2 files are created when we run the terraform code to build the cloud infra. You will also need the AmazonRootCA1.pem

**Run**

python device_runner.py

**1\. High-Level System Architecture & Thread Topology**

The system is designed around a **Single-Process, Multi-Threaded Model**. In Python, due to the Global Interpreter Lock (GIL), true CPU-bound parallelism is restricted on a single core. However, this application is strictly **I/O-bound** (waiting for camera sensor frame buffers, disk writes, and AWS network network sockets).

By splitting the logic into discrete threads, the operating system can context-switch between tasks instantly. If Thread A is waiting for an AWS MQTT network acknowledgment, the CPU instantly shifts context to Thread B to capture the next camera frame, ensuring zero frame loss.

**2\. Thread Synchronization & The Concurrency Control Layer**

When multiple threads access shared resources in memory, it introduces the risk of a **Race Condition**—where the state of a variable depends on the unpredictable order of thread execution.

![Thread Topology Diagram][image1]


* **The Mutex Primitive (threading.Lock)**: A Mutex (Mutual Exclusion) lock acts as a software semaphore. Only one thread can own the lock at any given microsecond.


* **The Critical Section**: The critical section is minimized to a single operational instruction: latest\_shared\_frame \= frame.copy(). Instead of passing a reference pointer (which would allow the Main Thread to read the memory *while* Thread B is modifying it), .copy() performs a deep pixel-by-pixel duplication in RAM. This isolates the memory addresses and guarantees thread safety.

**3\. State Machine: Automated Fleet Provisioning Lifecycle**

The script contains an automated provisioning state machine based on the **AWS IoT Fleet Provisioning by Claim** design pattern. It shifts through three distinct cryptographic phases:

![Thread Topology Diagram][image2]

1. **Bootstrap Phase**: The script looks for production certificates. If missing, it initiates a connection using the claim.cert.pem. This certificate has highly restricted privileges, only permitted to talk to the AWS provisioning topics.  
2. **Key Generation Phase**: The device publishes an empty payload to $aws/certificates/create/json. The AWS IoT Provisioning MQTT broker executes an internal lambda, mints a brand-new certificate/private key pair specifically for this unit, and sends it back across the encrypted channel.  
3. **Registration Phase**: The script saves these keys to disk, then sends an activation request to the template topic along with its hardcoded parameter {"SerialNumber": "MPC-SN-001"}. AWS evaluates the template, registers the device into the IoT Core Registry, and applies the correct production security policies.  
4. **Transition to Operational State**: The bootstrap connection is destroyed. The application shifts states permanently, using the new perm.cert.pem profiles moving forward.

**4\. Telemetry Engine & Network Socket Optimization**

Thread A handles the sensor telemetric ingest pipelines.

* **mTLS (Mutual TLS) Protocol**: Communications are wrapped in a dual-handshake TLS v1.3 socket over port 8883\. Not only does the device verify that it is talking to a genuine AWS endpoint via the AmazonRootCA1.pem, but AWS actively challenges and verifies the device's identity using the client-side perm.cert.pem.  
* **MQTT QoS 1 (At Least Once Delivery)**: Telemetry is sent with Quality of Service Level 1\. This initiates a packet tracking loop:  
  1. The client publishes an MQTT\_PUBLISH packet.  
  2. The client waits for a PUBACK (Publish Acknowledgment) packet from AWS.  
  3. If the network drops and PUBACK is not received within a timeout window, the client automatically re-transmits the payload with a duplicate (DUP) flag set. This ensures data integrity over unstable Wi-Fi or cellular gateways.

**5\. Media Pipeline: Time-Sliced Ring Buffer Architecture**

Thread B processes raw optical arrays via the Windows DirectShow engine. The media management pipeline follows a **segmented ring buffer sequence**:

![Thread Topology Diagram][image3]

* **Codec Optimization**: By initializing cv2.VideoWriter\_fourcc(\*'XVID') into an .mkv (Matroska) container format, the stream becomes highly resilient to power loss. Unlike standard MP4 containers—which store their master frame index metadata block (moov atom) at the very end of the file closure process—MKV structures use linear, continuous block-element formatting. If the edge computer loses power mid-recording, the clip remains fully readable up to the exact millisecond before the power failure.  
* **HTTP Content-Type Binding**: When the 10-second file is finalized, the boto3 SDK uploads it to S3. Crucially, it injects the header ExtraArgs={'ContentType': 'video/x-matroska'}. Without this, S3 defaults the object stream to an anonymous binary/octet-stream download block. Forcing the MIME type ensures that downstream web applications or media services can stream the video directly in native players without needing to download it locally first.

**6\. Main GUI Loop & Windows Operating System Constraints**

Windows 11 manages Desktop Window Manager (DWM) display handles and window messages (like mouse clicks, repositioning, and key presses) strictly inside a localized **Single Threaded Apartment (STA)** model.

* **The GUI Trap**: If cv2.imshow() is executed inside a background thread, the background thread attempts to inject visual graphics elements into the OS GUI sub-system. Windows will classify this as an illegal cross-thread operation, resulting in a frozen window (the notorious "Not Responding" state) or a total crash of the Python interpreter application.  
* **The Windows Solution**: Thread B performs all the computational heavy lifting (camera capture, file indexing, encoding, and cloud uploading) completely decoupled from the interface. It drops the completed image matrices into the shared memory segment. The Root Main Thread handles nothing but drawing that image array using cv2.imshow and ticking the Windows window messaging queue loop via cv2.waitKey(1). This guarantees a highly stable application UI under Windows 11\.

**Integrated IoT Device Automation System Architecture**

This software establishes a highly resilient, non-blocking telemetry and edge video management agent optimized for Windows 11 hardware environments.

The software utilizes an asynchronous multi-threaded pattern (threading.Thread) combined with thread-safe atomic resource passing (threading.Lock()). This structure decouples network input/output (I/O) bounds from local hardware frame capture loops, ensuring sensor telemetry transmission survives uninhibited even if extreme camera frame-drops or network-bound S3 transmission timeouts occur.

![Thread Topology Diagram][image4]

**Module 1: Global Configurations & Video Formatting Engine**

Python

![Thread Topology Diagram][image5]


* **Endpoint Variables:** Contains your distinct AWS MQTT regional gateways, AWS IoT Registry Provisioning Template names, and the hardware identifier variable (SERIAL\_NUMBER).  
* **Media Configuration Parameters:** Maps frame properties (FRAME\_WIDTH, FRAME\_HEIGHT, FPS) and sets the video slice length using CHUNK\_DURATION\_SEC \= 10.  
* **Dynamic Container Mapping Engine:** Translates a simple string parameter (CHOSEN\_FORMAT) into discrete operating system instructions. It automatically configures the appropriate FourCC binary codec identifier (mp4v, XVID, or MJPG), matches local file handlers (.mp4, .mkv, .avi), and sets the structural HTTP header MIME attribute (CONTENT\_TYPE) required for clean web browser rendering out of Amazon S3.

**Module 2: Thread Synchronization State & Thread Interprocess Communication**

Python


![Thread Topology Diagram][image6]

* **frame\_lock (Mutex Threading Lock):** Establishes an atomic locking primitive. Because separate threads are concurrently trying to write to and read from the exact same image matrix in RAM, the lock prevents data race conditions (which would result in visual artifacting or a hard Python interpreter segmentation fault).  
* **latest\_shared\_frame:** Acts as a shared pointer holding the most recent numpy image matrix parsed from the device camera sensor.  
* **system\_running:** A global boolean flag acting as an interrupt vector. When flipped to False, it immediately cascades down to all execution sub-loops, ensuring background worker pipelines drop hardware resource locks and exit smoothly.

**Module 3: Fleet Provisioning Lifecycle Handler**

Python

![Thread Topology Diagram][image7]

* **Automated Device Onboarding:** This layer handles the "Fleet Provisioning by Claim" protocol. If the device detects it does not possess operational credentials on disk, it initializes a short-lived bootstrap connection to AWS IoT Core utilizing temporary bootstrap credentials (claim.cert.pem).  
* **Asynchronous Pub/Sub Hooks:** Subscribes to the restricted system topics ($aws/certificates/create/json/accepted and $aws/provisioning-templates/...).  
* **Key Rotation & Registration:** Upon receipt of a valid registration response from AWS, it intercepts the newly minted production keys, payload strings, and ownership tokens. It writes permanent credentials (perm.cert.pem / perm.private.key) cleanly to your disk, triggers AWS registration, and kills the bootstrap context.

**Module 4: Thread A \- Telemetry Loop (AWS IoT Core MQTT Pipeline)**

Python


![Thread Topology Diagram][image8]

* **mTLS Channel Setup:** Initializes a dedicated, cryptographic TLS v1.3 tunnel to your AWS IoT endpoints using the permanent x509 digital certificates saved during onboarding.  
* **Asynchronous Sensor Simulation:** Iterates from 1 to 10 every 30 seconds, fabricating simulation payloads packed with timestamps, sensor identifiers, random floating-point float arrays simulating ambient temperature readings, and operation bits.  
* **High-Responsiveness Sleeping:** Instead of utilizing a flat time.sleep(30)—which would freeze the execution loop and ignore system termination events—the thread breaks down its idle phase into 30 distinct, single-second intervals. It performs an active check on system\_running during every pass, allowing the system to exit immediately without hanging when a shutdown is triggered.

**Module 5: Thread B \- Video Capturing & S3 Segmentation Pipeline**

Python

![Thread Topology Diagram][image9]

* **cv2.CAP\_DSHOW (DirectShow Engine Integration):** Configures OpenCV to tap directly into the native Windows 11 DirectShow multimedia pipeline. This completely bypasses default virtual layer processing delays, resulting in rapid frame updates and low CPU overhead.  
* **Atomic Frame Dispatch:** As raw image frames loop off the camera sensor hardware layer, they are deeply duplicated in memory via frame.copy(). The code acquires the lock (with frame\_lock:), safely rewrites latest\_shared\_frame, and immediately drops the lock to avoid stalling the video loop.  
* **Automated Video Chunk Storage Lifecycle:** \`\`\` \[Webcam Sensor\] ──► RAM Buffer ──► cv2.VideoWriter (temp\_output.mkv) │ (Hits CHUNK\_DURATION\_SEC / 10s) │ ▼ video\_writer.release() ──► boto3 S3 Upload ──► os.remove()

Every 10 seconds, the active \`VideoWriter\` binary stream handle is cleanly closed and committed to disk. A separate, asynchronous background task fires up via \`boto3\`, sending the file chunk straight to Amazon S3 using multi-part stream handling headers while a new \`VideoWriter\` file starts caching the next sequence. Once the upload finishes, \`os.remove()\` cleans the disk segment to maintain zero-waste local memory tracking.

\---

**Module 6: Execution Context Orchestration & Main GUI Event Thread**

![Thread Topology Diagram][image10]

* **Why Daemon Threads are Used:** Both execution pipelines are initiated with daemon=True. This marks them as subordinate processes. If the main program stops or crashes, Windows terminates these background workers instantly, avoiding orphaned threads that could lock up webcam hardware or leak network sockets.  
* **Conforming to the Windows 11 GUI Rendering Architecture:** Windows 11 requires user interface rendering tasks (cv2.imshow) and desktop event processing loops to execute strictly from the application's root execution path (the main thread).  
* **The Execution Render Hook:** The main loop monitors changes to latest\_shared\_frame across a thread-safe boundary. It retrieves the matrix, handles desktop window painting events using cv2.waitKey(1), and checks for user keystrokes (q) or terminal interrupt signals (Ctrl+C).  
* **Graceful Resource Deallocation:** If a stop event is triggered, system\_running flips to False. The program waits for background network connections to close, safely deallocates your physical webcam hardware handle via cap.release(), tears down GUI frames with cv2.destroyAllWindows(), and terminates cleanly.

**Based on the full source code provided in both files, AWS Kinesis (or Kinesis Video Streams) is not actually used anywhere in the code.**

**The script is entirely built around two different AWS services:**

1. **AWS IoT Core (awsiotsdk / awscrt): Used for the automated device fleet provisioning lifecycle and pushing structured MQTT JSON temperature packets to topics like fleet/sensors/{i} every 30 seconds.**

2. **Amazon S3 (boto3): Used to upload time-sliced, 10-second video clip chunks (.mp4, .mkv, or .avi) saved by OpenCV on the local disk directly into an S3 bucket (minipc-iot-simulation-255945442255) via standard HTTPS PUT requests.**

**Where the Confusion Comes From**

**There are a few remnant configuration placeholders left in the code's configuration section that reference Kinesis, but they are completely unused variables:**

**Python**

**![][image11]**

![Thread Topology Diagram][image11]

**\# Unused placeholder strings left over in the file setup:**

**ROLE\_ALIAS \= "KvsCameraRoleAlias"      \# KVS stands for Kinesis Video Streams**

**STREAM\_NAME \= "FHD\_Security\_Camera\_Stream"**

**Historically, to stream video to AWS Kinesis Video Streams from a local IOT device, you would need to use either the AWS Kinesis Video Streams Producer SDK (C++ or Java, no python) or integrate a dedicated GStreamer plugin loop (kvssink).**

**Instead of dealing with that real-time streaming pipeline, this code utilizes a simpler file-upload approach using regular Amazon S3 via boto3.client('s3'). It handles the video files as individual static object chunks rather than a continuous live RTSP/WebRTC Kinesis video stream. KVS does not store the video directly. Note that we will still need to define a Lambda function to store video chunks files to S3.** 

        
======================================================================
  IMAGE PATH DEFINITIONS (Keep these together at the bottom of the file)
======================================================================
[image1]: images/Picture1.png
[image2]: images/Picture2.png
[image3]: images/Picture3.png
[image4]: images/Picture4.png
[image5]: images/Picture5.png
[image6]: images/Picture6.png
[image7]: images/Picture7.png
[image8]: images/Picture8.png
[image9]: images/Picture9.png
[image10]: images/Picture10.png
[image11]: images/Picture11.png


