# TurboPi Beam Bots Architecture

## Overview

Replace the ROS2 Docker stack with an Elixir/Phoenix application that:
- Controls hardware via serial protocol
- Serves a web UI for control and camera feed
- Starts automatically on boot
- Is more hackable and fun to develop

---

## 1. Docker Strategy: Disable, Don't Delete

Keep Docker as a fallback. Just prevent it from starting.

```bash
# Disable Docker auto-start
docker update --restart=no TurboPi

# Or disable the service that starts it
sudo systemctl disable docker

# To go back to stock:
docker update --restart=always TurboPi
sudo systemctl enable docker
```

---

## 2. Project Structure: Phoenix Umbrella

One umbrella project with multiple apps:

```
turbopi/
├── mix.exs                     # Umbrella config
├── apps/
│   ├── board/                  # Hardware driver
│   │   ├── lib/
│   │   │   ├── board.ex        # Main GenServer
│   │   │   ├── protocol.ex     # Packet building/parsing
│   │   │   ├── crc8.ex         # Checksum
│   │   │   ├── servo.ex        # Servo commands
│   │   │   ├── motor.ex        # Motor commands
│   │   │   └── sensors.ex      # IMU, battery, etc.
│   │   └── mix.exs
│   │
│   ├── vision/                 # Camera & CV (optional, can add later)
│   │   ├── lib/
│   │   │   ├── camera.ex       # Frame capture
│   │   │   └── tracker.ex      # Color/object tracking
│   │   └── mix.exs
│   │
│   └── control_web/            # Phoenix web interface
│       ├── lib/
│       │   ├── control_web/
│       │   │   ├── live/
│       │   │   │   ├── dashboard_live.ex   # Main control page
│       │   │   │   └── camera_live.ex      # Camera feed
│       │   │   ├── components/
│       │   │   │   ├── joystick.ex         # Virtual joystick
│       │   │   │   └── servo_control.ex    # Gimbal sliders
│       │   │   └── channels/
│       │   │       └── robot_channel.ex    # Real-time commands
│       │   └── control_web.ex
│       └── mix.exs
│
└── config/
    ├── config.exs
    ├── dev.exs
    └── prod.exs
```

### Why Umbrella?

- **Separation of concerns**: Hardware, vision, and web are independent
- **Can develop board driver on Mac** with a mock serial port
- **Easy to add more apps** (ML, navigation, etc.)
- **Each app has its own supervision tree**

---

## 3. Supervision Tree

```
TurboPi.Application
├── Board.Supervisor
│   ├── Board.Connection      # GenServer: serial port
│   ├── Board.Receiver        # GenServer: parse incoming packets
│   └── Board.CommandQueue    # GenServer: rate-limit outgoing commands
│
├── Vision.Supervisor (optional)
│   ├── Vision.Camera         # GenServer: frame capture
│   └── Vision.Pipeline       # GenServer: CV processing
│
└── ControlWeb.Supervisor
    ├── Phoenix.Endpoint
    └── Phoenix.PubSub
```

**Fault tolerance**: If camera crashes, board keeps running. If web crashes, hardware stays safe.

---

## 4. Phoenix LiveView for Controls

Real-time control without writing JavaScript:

```elixir
# lib/control_web/live/dashboard_live.ex
defmodule ControlWeb.DashboardLive do
  use ControlWeb, :live_view

  def mount(_params, _session, socket) do
    # Subscribe to battery updates
    if connected?(socket), do: Board.subscribe()

    {:ok, assign(socket,
      battery: Board.get_battery(),
      pan: 1500,
      tilt: 1500
    )}
  end

  def handle_event("move", %{"direction" => dir}, socket) do
    case dir do
      "forward"  -> Board.Motor.forward(50)
      "back"     -> Board.Motor.backward(50)
      "left"     -> Board.Motor.strafe_left(50)
      "right"    -> Board.Motor.strafe_right(50)
      "stop"     -> Board.Motor.stop()
    end
    {:noreply, socket}
  end

  def handle_event("gimbal", %{"pan" => pan, "tilt" => tilt}, socket) do
    Board.Servo.set_position(5, pan)
    Board.Servo.set_position(6, tilt)
    {:noreply, assign(socket, pan: pan, tilt: tilt)}
  end

  def handle_info({:battery_update, voltage}, socket) do
    {:noreply, assign(socket, battery: voltage)}
  end
end
```

```heex
# lib/control_web/live/dashboard_live.html.heex
<div class="dashboard">
  <div class="status">
    Battery: <%= @battery %>mV
  </div>

  <div class="controls">
    <button phx-click="move" phx-value-direction="forward">↑</button>
    <div>
      <button phx-click="move" phx-value-direction="left">←</button>
      <button phx-click="move" phx-value-direction="stop">■</button>
      <button phx-click="move" phx-value-direction="right">→</button>
    </div>
    <button phx-click="move" phx-value-direction="back">↓</button>
  </div>

  <div class="gimbal">
    <input type="range" min="500" max="2500" value={@pan}
           phx-change="gimbal" name="pan" />
    <input type="range" min="500" max="2500" value={@tilt}
           phx-change="gimbal" name="tilt" />
  </div>
</div>
```

---

## 5. Auto-Start on Boot

Create a systemd service:

```bash
# /etc/systemd/system/turbopi-elixir.service
[Unit]
Description=TurboPi Elixir Controller
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/turbopi
Environment=MIX_ENV=prod
Environment=PORT=4000
ExecStart=/home/pi/turbopi/_build/prod/rel/turbopi/bin/turbopi start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
# Enable it
sudo systemctl enable turbopi-elixir
sudo systemctl start turbopi-elixir

# View logs
sudo journalctl -u turbopi-elixir -f
```

---

## 6. Development Workflow

### On Pi (production):
```bash
cd /home/pi/turbopi
git pull
MIX_ENV=prod mix do deps.get, compile, release
sudo systemctl restart turbopi-elixir
```

### On Mac (development):
```bash
# Mock the serial port for testing
cd turbopi
iex -S mix phx.server

# Opens http://localhost:4000
# Board commands go to a mock that logs them
```

### Deploy from Mac:
```bash
# Build release on Pi (ARM)
ssh pi@192.168.0.90 "cd turbopi && git pull && MIX_ENV=prod mix release"
```

---

## 7. Camera Feed Options

### Option A: MJPEG Stream (Simple)
```elixir
# Use existing MJPEG streamer, embed in Phoenix
<img src="http://192.168.0.90:8080/stream" />
```

### Option B: Elixir Native (More Control)
```elixir
# Use evision (OpenCV) + Broadway for frame pipeline
defmodule Vision.Camera do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    # OpenCV capture
    {:ok, cap} = Evision.VideoCapture.videoCapture(0)
    schedule_frame()
    {:ok, %{capture: cap, frame: nil}}
  end

  def handle_info(:capture, state) do
    {:ok, frame} = Evision.VideoCapture.read(state.capture)
    Phoenix.PubSub.broadcast(TurboPi.PubSub, "camera", {:frame, frame})
    schedule_frame()
    {:noreply, %{state | frame: frame}}
  end

  defp schedule_frame, do: Process.send_after(self(), :capture, 33) # ~30fps
end
```

---

## 8. Comparison: ROS2 vs Elixir Stack

| Aspect | ROS2 Docker | Elixir/Phoenix |
|--------|-------------|----------------|
| Startup time | ~30 seconds | ~2 seconds |
| Memory usage | ~500MB+ | ~50MB |
| Hot reload | No | Yes |
| Web UI | Separate rosbridge | Built-in LiveView |
| Fault tolerance | Manual | Supervision trees |
| Learning curve | ROS concepts | Elixir/OTP |
| Community | Large robotics | Growing, fun |

---

## 9. Implementation Order

### Phase 1: Core Driver (Weekend 1)
1. Create umbrella project
2. Implement `Board.Protocol` (packet building, CRC8)
3. Implement `Board.Connection` (serial port GenServer)
4. Test with LED: `Board.set_rgb(1, 255, 0, 0)`
5. Add motors and servos

### Phase 2: Web UI (Weekend 2)
1. Add Phoenix app to umbrella
2. Create basic dashboard LiveView
3. Add motor controls (buttons)
4. Add gimbal controls (sliders)
5. Show battery status

### Phase 3: Camera & Polish (Weekend 3)
1. Integrate camera feed
2. Add keyboard controls
3. Mobile-friendly CSS
4. Deploy as release

### Phase 4: Vision & AI (Ongoing)
1. Add color tracking
2. Integrate with Beam Bots topology DSL
3. Add ML models (Nx/Bumblebee)

---

## 10. Key Dependencies

```elixir
# apps/board/mix.exs
defp deps do
  [
    {:circuits_uart, "~> 1.5"},   # Serial port
  ]
end

# apps/vision/mix.exs (optional)
defp deps do
  [
    {:evision, "~> 0.1"},         # OpenCV bindings
    {:nx, "~> 0.6"},              # Numerical computing
  ]
end

# apps/control_web/mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_html, "~> 4.0"},
  ]
end
```

---

## Quick Start Commands

```bash
# On Pi
cd ~
mix archive.install hex phx_new

# Create umbrella
mix new turbopi --umbrella
cd turbopi/apps

# Create apps
mix new board
mix phx.new control_web --no-ecto --no-mailer

# Run it
cd ../..
iex -S mix phx.server
```
