# TurboPi Elixir Controller

Elixir/Phoenix replacement for the ROS2 Docker stack on Hiwonder TurboPi robot.

## Features

- Web-based control dashboard (Phoenix LiveView)
- Motor controls with adjustable speed (WASD + QE keys)
- Gimbal pan/tilt control (arrow keys)
- Live camera streaming (MJPEG) with distance HUD overlay
- Collision avoidance (auto-stops at 10cm from obstacles)
- Power monitor with voltage history graph
- 4 RGB LEDs with state persistence: 2 on main board + 2 on ultrasonic sensor
- Ultrasonic distance sensor
- Battery voltage monitoring
- Buzzer control
- Auto-start on boot via systemd
- Mock mode for development on Mac

## Requirements

- Hiwonder TurboPi with Raspberry Pi 5
- Battery power (wall adapters cause undervoltage)
- Mac/Linux for development

## Quick Start

### First-Time Setup

```bash
# Clone the repo
git clone git@github.com:zgohr/ex_turbopi.git
cd ex_turbopi

# Run setup (takes 30-60 min for Erlang compile on Pi)
./setup.sh
```

This will:
1. Install asdf, Erlang 27.3, and Elixir 1.18.4 on the Pi
2. Disable the TurboPi Docker container
3. Build and deploy the Elixir app
4. Set up auto-start on boot

### Subsequent Deploys

```bash
./deploy.sh
```

### Access the Dashboard

Open `http://192.168.0.90:4000` in your browser.

## Development

Run locally on your Mac (mock mode - no hardware):

```bash
mix deps.get
iex -S mix phx.server
```

Open `http://localhost:4000`

## Project Structure

```
ex_turbopi_umbrella/
├── apps/
│   ├── board/           # Hardware drivers
│   │   ├── Board        # Main API (motors, servos, LEDs, buzzer, battery)
│   │   ├── Board.Connection  # Serial protocol (/dev/ttyAMA0)
│   │   ├── Board.Sonar  # I2C ultrasonic sensor (0x77)
│   │   ├── Board.Battery  # Battery voltage monitoring
│   │   ├── Board.Camera  # MJPEG camera streaming control
│   │   ├── Board.Telemetry  # Power usage telemetry
│   │   └── Board.LEDs     # LED state persistence
│   ├── ex_turbopi/      # Core application
│   └── ex_turbopi_web/  # Phoenix web interface
├── config/              # Configuration files
├── scripts/
│   ├── pi_setup.sh      # Pi setup script
│   └── camera_stream.py # Python MJPEG streaming server
├── setup.sh             # First-time setup (run from Mac)
└── deploy.sh            # Deploy updates (run from Mac)
```

## Hardware API

```elixir
# Motors
Board.drive(:forward, 50)   # direction, speed (0-100)
Board.drive(:backward, 50)
Board.drive(:left, 50)      # strafe
Board.drive(:right, 50)
Board.drive(:rotate_left, 50)
Board.drive(:rotate_right, 50)
Board.stop()

# Gimbal (servos 5=tilt, 6=pan)
Board.set_servo(5, 1500)    # servo_id, pulse (500-2500)
Board.set_servo(6, 1500)
Board.center_gimbal()

# Board RGB LEDs (2 LEDs on main board)
Board.set_rgb(1, 255, 0, 0) # led_id (1-2), r, g, b
Board.set_board_rgb(0, 255, 0)  # set both board LEDs
Board.board_rgb_off()

# Ultrasonic Sonar RGB LEDs (2 LEDs on sensor)
Board.Sonar.set_pixel(0, 255, 0, 0)  # led_id (0-1), r, g, b
Board.Sonar.set_rgb(0, 0, 255)       # set both sonar LEDs
Board.Sonar.off()

# Ultrasonic Distance
Board.Sonar.get_distance()  # returns {:ok, mm} or {:error, reason}

# Battery
Board.get_battery()         # returns {:ok, voltage_mv} or {:error, :no_data}

# Camera
Board.start_camera()        # starts MJPEG stream on port 5000
Board.stop_camera()         # stops camera stream
Board.camera_streaming?()   # returns true/false

# Buzzer
Board.beep()                # default 1000Hz, 0.1s
Board.beep(800, 0.5)        # freq, duration
```

## Pi Commands

```bash
# SSH to Pi
ssh pi@192.168.0.90  # password: raspberrypi

# Service management
sudo systemctl status ex_turbopi
sudo systemctl restart ex_turbopi
sudo systemctl stop ex_turbopi

# View logs
sudo journalctl -u ex_turbopi -f

# Check for undervoltage
dmesg | grep -i voltage
```

## Restore Original ROS2 Stack

```bash
ssh pi@192.168.0.90

# Re-enable Docker container
docker update --restart=always TurboPi

# Stop Elixir service
sudo systemctl stop ex_turbopi
sudo systemctl disable ex_turbopi

# Reboot
sudo reboot
```

## Configuration

Environment variables (set in systemd service):

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 4000 | HTTP port |
| `PHX_HOST` | Pi's IP | Hostname for URLs |
| `SECRET_KEY_BASE` | generated | Phoenix secret |

To change, edit `/etc/systemd/system/ex_turbopi.service` on the Pi.

## Troubleshooting

### Can't connect to Pi

```bash
# Check if Pi is on network
ping 192.168.0.90

# Or use different IP
PI_HOST=pi@192.168.0.123 ./setup.sh
```

### Servos not moving

1. Use battery power, not wall adapter
2. Check Docker is stopped: `docker ps`
3. Check serial port: `sudo lsof /dev/ttyAMA0`

### System keeps restarting

Undervoltage - use fully charged batteries:
```bash
dmesg | grep -i voltage
```

### Service won't start

```bash
# Check logs
sudo journalctl -u ex_turbopi -n 100

# Try running manually
cd /home/pi/ex_turbopi_umbrella
export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"
SECRET_KEY_BASE=$(cat .env | grep SECRET | cut -d= -f2) \
  _build/prod/rel/ex_turbopi_umbrella/bin/ex_turbopi_umbrella start
```

## Serial Protocol

The TurboPi uses a custom serial protocol:

```
Packet: 0xAA 0x55 [Function] [Length] [Data...] [CRC8]
Device: /dev/ttyAMA0
Baudrate: 1,000,000
```

See `apps/board/lib/board/protocol.ex` for implementation.

## License

MIT
