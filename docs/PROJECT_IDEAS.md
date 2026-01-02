# TurboPi Project Ideas

Focus: AI/ML Vision and Robotics Control

## Hardware Available

- HD Camera with 2-DOF pan/tilt gimbal (servos 5 & 6)
- 4x Mecanum wheels (omnidirectional movement)
- Ultrasonic distance sensor
- 4-channel line follower sensor
- Raspberry Pi 5 (quad-core 2.4GHz, 4GB+ RAM)

---

## Beginner - Computer Vision Fundamentals

### 1. Color Tracking Ball Chaser
Track a colored ball with OpenCV. Gimbal follows the ball, car drives toward it.

**Learn:** HSV color spaces, contour detection, PID control

**Steps:**
- Capture frames from camera
- Convert to HSV, threshold for target color
- Find contours, get centroid
- PID control to center gimbal on target
- Drive toward target when centered

### 2. Face Following Camera
Gimbal tracks your face using MediaPipe or Haar cascades.

**Learn:** Real-time face detection, servo smoothing

### 3. QR Code Navigator
Place QR codes around a room with commands. Robot scans, decodes, and executes.

**Learn:** Camera calibration, QR detection (pyzbar), state machines

---

## Intermediate - ML Models

### 4. Custom Object Detector with YOLOv5
Train YOLO to recognize specific objects (coffee mug, pet, etc.). Robot announces or follows detected objects.

**Learn:** Dataset collection, model training, inference optimization on Pi

**Steps:**
- Collect ~100+ images of target objects
- Label with LabelImg or Roboflow
- Train YOLOv5s (small) model
- Export to ONNX or TensorRT for Pi
- Run inference, trigger actions on detection

### 5. Gesture-Controlled Driving
Use MediaPipe hand tracking. Open palm = stop, point = direction.

**Learn:** Gesture classification, real-time inference

### 6. Traffic Sign Recognition Course
Print mini traffic signs, set up a course. Robot recognizes and obeys.

**Learn:** CNN classification, decision logic

---

## Advanced - Autonomous Systems

### 7. Visual SLAM & Mapping
Build a map of your room using camera + ultrasonic. Implement visual odometry.

**Learn:** Occupancy grids, localization, path planning, ORB-SLAM or similar

### 8. Voice + Vision Assistant
"Go to the red cup" → finds and navigates to it.

**Learn:** Multi-modal AI, speech recognition, task planning

**Components:**
- Whisper for speech-to-text
- LLM for intent parsing
- YOLO for object detection
- Navigation planner

### 9. Imitation Learning
Record yourself driving around obstacles. Train a neural net to mimic behavior.

**Learn:** Behavioral cloning, data collection, end-to-end learning

**Steps:**
- Collect (camera_frame, motor_commands) pairs while driving
- Train CNN to predict commands from images
- Deploy and let robot drive autonomously

### 10. Reinforcement Learning Navigator
Train the robot to navigate to goals using RL. Reward for reaching target, penalty for collisions.

**Learn:** Sim-to-real, reward shaping, policy gradients

---

## Beam Bots Integration

[Beam Bots](https://beambots.dev/) is an Elixir/OTP framework for fault-tolerant robotics. Could replace the ROS2 Docker stack with something more hackable.

### Why Beam Bots?
- Elixir's supervision trees = self-healing robot
- Hot code reloading = update code without restarting
- Lightweight compared to ROS2
- Fun to learn functional programming + robotics

### Integration Approach

#### 1. Install Elixir on Pi
```bash
sudo apt install erlang elixir
```

#### 2. Create BB Project
```bash
mix new turbopi_bb
cd turbopi_bb
# Add {:bb, "~> 0.1"} to mix.exs
mix deps.get
```

#### 3. Write Serial Driver for Controller Board

The TurboPi uses a custom serial protocol to an STM32 controller. Need to port the Python SDK to Elixir:

```elixir
defmodule TurboPi.Board do
  use GenServer

  @serial_port "/dev/ttyAMA0"
  @baudrate 1_000_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def set_servo(servo_id, pulse_width) do
    GenServer.cast(__MODULE__, {:servo, servo_id, pulse_width})
  end

  def set_motor(motor_id, speed) do
    GenServer.cast(__MODULE__, {:motor, motor_id, speed})
  end

  # Implement protocol from ros_robot_controller_sdk.py
  # Packet format: 0xAA 0x55 Function Length Data Checksum
end
```

#### 4. Define Robot Topology
```elixir
defmodule TurboPi do
  use BB

  topology do
    link :base do
      # Mecanum wheel base
      joint :front_left_wheel, type: :continuous
      joint :front_right_wheel, type: :continuous
      joint :rear_left_wheel, type: :continuous
      joint :rear_right_wheel, type: :continuous

      # Camera gimbal
      joint :pan, type: :revolute do
        limit do
          lower(~u(-90 degree))
          upper(~u(90 degree))
        end
        link :tilt_base do
          joint :tilt, type: :revolute do
            limit do
              lower(~u(-45 degree))
              upper(~u(45 degree))
            end
            link :camera
          end
        end
      end
    end
  end
end
```

#### 5. Add Vision Pipeline
Use Evision (OpenCV bindings) or Nx for ML:

```elixir
defmodule TurboPi.Vision do
  def track_color(frame, target_hsv) do
    frame
    |> Evision.cvtColor(Evision.Constant.cv_COLOR_BGR2HSV())
    |> Evision.inRange(lower_bound, upper_bound)
    |> find_centroid()
  end
end
```

### Beam Bots Project Ideas

1. **Fault-Tolerant Explorer** - If camera crashes, keep driving with ultrasonic only
2. **LiveView Dashboard** - Phoenix web UI showing camera feed + controls
3. **Multi-Robot Coordination** - Elixir distribution for robot swarms
4. **Hot-Reload Behaviors** - Update tracking algorithm without stopping robot

---

## Recommended Learning Path

1. **Start:** Color Tracking (#1) - builds OpenCV + control fundamentals
2. **Then:** YOLOv5 Training (#4) - real ML pipeline
3. **Then:** Voice + Vision (#8) or Imitation Learning (#9) - full system integration
4. **Parallel:** Beam Bots serial driver - learn Elixir while building

---

## Resources

- [TurboPi Docs](https://docs.hiwonder.com/projects/TurboPi/en/advanced/)
- [Beam Bots](https://beambots.dev/) | [Hex Docs](https://hexdocs.pm/bb)
- [YOLOv5](https://github.com/ultralytics/yolov5)
- [MediaPipe](https://developers.google.com/mediapipe)
- [OpenCV Python](https://docs.opencv.org/4.x/d6/d00/tutorial_py_root.html)
