#!/usr/bin/env python3
"""
MJPEG Camera Streaming Server for TurboPi

Streams the Pi camera as MJPEG over HTTP.
- /stream - MJPEG video stream
- /status - Health check endpoint
- /snapshot - Single JPEG frame

Usage:
    python3 camera_stream.py [--port 5000] [--width 640] [--height 480]
"""

import argparse
import io
import logging
import signal
import sys
import threading
import time

# Flask for HTTP server
from flask import Flask, Response, jsonify

# Picamera2 for camera access
from picamera2 import Picamera2

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global camera instance
camera = None
streaming = False
frame_lock = threading.Lock()
current_frame = None


def capture_frames():
    """Background thread to capture frames continuously."""
    global current_frame, streaming, camera

    import cv2
    import numpy as np

    frame_count = 0
    while streaming and camera is not None:
        try:
            # Capture frame as numpy array
            frame = camera.capture_array()

            # Log shape once for debugging
            if frame_count == 0:
                logger.info(f"Frame shape: {frame.shape}, dtype: {frame.dtype}")

            # Handle different formats from picamera2
            if len(frame.shape) == 2:
                # Grayscale - convert to BGR
                frame = cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)
            elif len(frame.shape) == 3:
                if frame.shape[2] == 2:
                    # YUYV format (common on Pi cameras) - convert to BGR
                    frame = cv2.cvtColor(frame, cv2.COLOR_YUV2BGR_YUYV)
                elif frame.shape[2] == 4:
                    # RGBA/BGRA - convert to BGR
                    frame = cv2.cvtColor(frame, cv2.COLOR_BGRA2BGR)
                elif frame.shape[2] == 3:
                    # RGB or BGR - assume RGB from picamera2 and convert
                    frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
                # else 3 channels should work

            # Ensure contiguous array
            if not frame.flags['C_CONTIGUOUS']:
                frame = np.ascontiguousarray(frame)

            # Encode to JPEG - lower quality for faster streaming
            success, jpeg = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 50])

            if success:
                with frame_lock:
                    current_frame = jpeg.tobytes()

            frame_count += 1

        except Exception as e:
            logger.error(f"Frame capture error: {e}")
            time.sleep(0.1)
            continue

        # Small delay to control frame rate (~20 fps)
        time.sleep(0.05)


def generate_frames():
    """Generator yielding MJPEG frames."""
    global current_frame

    while streaming:
        with frame_lock:
            frame = current_frame

        if frame is not None:
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')
        else:
            time.sleep(0.05)


@app.route('/stream')
def stream():
    """MJPEG stream endpoint."""
    if not streaming:
        return "Camera not started", 503

    return Response(
        generate_frames(),
        mimetype='multipart/x-mixed-replace; boundary=frame'
    )


@app.route('/snapshot')
def snapshot():
    """Single JPEG frame endpoint."""
    global current_frame

    if not streaming or current_frame is None:
        return "Camera not started", 503

    with frame_lock:
        frame = current_frame

    if frame is None:
        return "No frame available", 503

    return Response(frame, mimetype='image/jpeg')


@app.route('/status')
def status():
    """Health check endpoint."""
    return jsonify({
        'streaming': streaming,
        'camera': camera is not None
    })


@app.route('/')
def index():
    """Simple HTML page with embedded stream."""
    if not streaming:
        return "<h1>Camera not started</h1><p>Start the camera to view stream.</p>"

    return '''
    <!DOCTYPE html>
    <html>
    <head><title>TurboPi Camera</title></head>
    <body style="margin:0; background:#000;">
        <img src="/stream" style="width:100%; height:auto;">
    </body>
    </html>
    '''


def start_camera(width=640, height=480):
    """Initialize and start the camera."""
    global camera, streaming

    logger.info(f"Starting camera: {width}x{height}")

    try:
        camera = Picamera2()

        # Simple preview configuration - RGB888 is more universally supported
        config = camera.create_preview_configuration(
            main={"size": (width, height), "format": "RGB888"}
        )
        camera.configure(config)
        camera.start()

        streaming = True

        # Start frame capture thread
        capture_thread = threading.Thread(target=capture_frames, daemon=True)
        capture_thread.start()

        logger.info("Camera started successfully")
        return True

    except Exception as e:
        logger.error(f"Failed to start camera: {e}")
        stop_camera()
        return False


def stop_camera():
    """Stop the camera and release resources."""
    global camera, streaming, current_frame

    streaming = False
    time.sleep(0.2)  # Let capture thread stop

    if camera is not None:
        try:
            camera.stop()
        except Exception:
            pass
        try:
            camera.close()
        except Exception as e:
            logger.error(f"Error closing camera: {e}")
        camera = None

    current_frame = None
    logger.info("Camera stopped")


def signal_handler(sig, frame):
    """Handle shutdown signals gracefully."""
    logger.info("Shutting down...")
    stop_camera()
    sys.exit(0)


def main():
    parser = argparse.ArgumentParser(description='TurboPi Camera Streaming Server')
    parser.add_argument('--port', type=int, default=5000, help='HTTP port (default: 5000)')
    parser.add_argument('--width', type=int, default=640, help='Frame width (default: 640)')
    parser.add_argument('--height', type=int, default=480, help='Frame height (default: 480)')
    parser.add_argument('--host', default='0.0.0.0', help='Bind host (default: 0.0.0.0)')
    args = parser.parse_args()

    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start camera
    if not start_camera(args.width, args.height):
        logger.error("Failed to initialize camera")
        sys.exit(1)

    # Run Flask server
    logger.info(f"Starting HTTP server on {args.host}:{args.port}")
    try:
        # Use threaded mode for handling multiple clients
        app.run(host=args.host, port=args.port, threaded=True, use_reloader=False)
    finally:
        stop_camera()


if __name__ == '__main__':
    main()
