# Board

Hardware driver library for the TurboPi robot controller.

## Modules

### Board

Main API for controlling the robot. Provides high-level functions for motors, servos, LEDs, buzzer, and battery.

```elixir
# Motors (Mecanum wheels)
Board.drive(:forward, 50)       # direction, speed (0-100)
Board.drive(:backward, 50)
Board.drive(:left, 50)          # strafe left
Board.drive(:right, 50)         # strafe right
Board.drive(:forward_left, 50)  # diagonal movement
Board.drive(:forward_right, 50)
Board.drive(:backward_left, 50)
Board.drive(:backward_right, 50)
Board.drive(:rotate_left, 50)   # spin in place
Board.drive(:rotate_right, 50)
Board.stop()

# Gimbal (servos 5=tilt, 6=pan)
Board.set_servo(5, 1500)       # servo_id, pulse (500-2500)
Board.center_gimbal()

# RGB LEDs (2 on main board)
Board.set_rgb(1, 255, 0, 0)    # led_id, r, g, b
Board.set_board_rgb(0, 255, 0) # set both
Board.board_rgb_off()

# Buzzer
Board.beep()                   # 1000Hz, 0.1s
Board.beep(800, 0.5)           # freq, duration

# Battery
Board.get_battery()            # {:ok, voltage_mv}
```

### Board.Connection

Low-level serial connection to the STM32 controller board.

- Device: `/dev/ttyAMA0`
- Baudrate: 1,000,000
- Protocol: `0xAA 0x55 [Function] [Length] [Data...] [CRC8]`

Supports subscribing to incoming packets by function code.

### Board.Sonar

I2C driver for the Hiwonder ultrasonic sensor with RGB LEDs.

- I2C Bus: `i2c-1`
- Address: `0x77`

```elixir
Board.Sonar.get_distance()       # {:ok, mm} (0-5000)
Board.Sonar.set_rgb(255, 0, 0)   # set both LEDs
Board.Sonar.set_pixel(0, 0, 255, 0)  # set single LED
Board.Sonar.off()
```

### Board.Battery

Battery voltage monitoring. Parses system packets from the controller.

```elixir
{:ok, voltage_mv} = Board.Battery.get_voltage()  # e.g., 12400 = 12.4V
{:ok, percentage} = Board.Battery.get_percentage()  # 0-100%
```

**Voltage Levels (2S 18650):**
- Full: ~8.4V (8400 mV)
- Nominal: ~7.4V (7400 mV)
- Low: ~6.4V (6400 mV)
- Critical: ~6.0V (6000 mV)

### Board.Camera

Controls the MJPEG camera streaming server (Python/Flask on port 5000).

```elixir
Board.start_camera()       # Start streaming
Board.stop_camera()        # Stop streaming
Board.camera_streaming?()  # Check status
```

Stream URL: `http://<pi-ip>:5000/stream`

### Board.Telemetry

Collects and broadcasts power usage telemetry for the LiveView dashboard.

Data is aggregated into 30-second windows, tracking:
- Average voltage per window
- Motor activity (% of time motors were running)
- Camera activity (% of time camera was on)
- 20 windows = 10 minutes of history

This allows correlating voltage drops with motor/camera usage.

```elixir
Board.Telemetry.subscribe()   # Subscribe to PubSub updates
Board.Telemetry.get_state()   # Get current telemetry state
```

### Board.LEDs

Tracks LED state for all 4 LEDs (2 board + 2 sonar) for persistence across page refreshes.

State is automatically updated when LEDs are set via `Board.set_rgb/4` or `Board.Sonar.set_pixel/4`.

```elixir
Board.LEDs.get_all()          # Get all LED states as map
Board.LEDs.get(:board1)       # Get single LED state
```

## Architecture

```
Board.Application (Supervisor)
├── Board.Connection  # Serial port GenServer
├── Board.Sonar       # I2C sensor GenServer
├── Board.Battery     # Battery monitoring GenServer
├── Board.Camera      # Camera streaming control
├── Board.Telemetry   # Power usage telemetry
└── Board.LEDs        # LED state persistence
```

All modules run as supervised GenServers. If hardware is unavailable (e.g., running on Mac), they operate in mock mode and log commands instead.

## Protocol Reference

See `lib/board/protocol.ex` for packet encoding/decoding. Function codes:

| Code | Function |
|------|----------|
| 0x00 | SYS (battery, system status) |
| 0x01 | LED |
| 0x02 | Buzzer |
| 0x03 | Motor |
| 0x04 | PWM Servo |
| 0x05 | Bus Servo |
| 0x06 | Key (button input) |
| 0x07 | IMU |
| 0x08 | Gamepad |
| 0x09 | SBUS (RC receiver) |
| 0x0A | OLED |
| 0x0B | RGB LED |
