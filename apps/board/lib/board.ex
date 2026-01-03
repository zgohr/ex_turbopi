defmodule Board do
  @moduledoc """
  High-level API for controlling the TurboPi robot.

  ## Examples

      # Set RGB LED to red
      Board.set_rgb(1, 255, 0, 0)

      # Move gimbal servos
      Board.set_servo(5, 1500)  # pan center
      Board.set_servo(6, 1500)  # tilt center

      # Drive motors
      Board.drive(:forward, 50)
      Board.stop()

      # Beep
      Board.beep()
  """

  alias Board.Connection

  # ---- RGB LED ----

  @doc """
  Set RGB LED color.
  led_id: 1-based LED index
  r, g, b: 0-255
  """
  def set_rgb(led_id, r, g, b) do
    Connection.set_rgb([{led_id, r, g, b}])
    # Track state for persistence
    led_key = String.to_atom("board#{led_id}")
    Board.LEDs.set(led_key, %{r: r, g: g, b: b})
  end

  @doc """
  Set both board RGB LEDs to the same color.
  The board has 2 LEDs (1 and 2).
  """
  def set_board_rgb(r, g, b) do
    Connection.set_rgb([{1, r, g, b}, {2, r, g, b}])
    # Track state for persistence
    Board.LEDs.set(:board1, %{r: r, g: g, b: b})
    Board.LEDs.set(:board2, %{r: r, g: g, b: b})
  end

  @doc """
  Turn off RGB LED.
  """
  def rgb_off(led_id \\ 1) do
    set_rgb(led_id, 0, 0, 0)
  end

  @doc """
  Turn off both board LEDs.
  """
  def board_rgb_off do
    set_board_rgb(0, 0, 0)
  end

  # ---- Servos ----

  @doc """
  Set PWM servo position.
  servo_id: 1-6 (gimbal is 5=pan, 6=tilt)
  pulse: 500-2500 (center is ~1500)
  duration: movement time in seconds (default 0.5)
  """
  def set_servo(servo_id, pulse, duration \\ 0.5) do
    Connection.set_pwm_servo(duration, [{servo_id, pulse}])
  end

  @doc """
  Set multiple servos at once.
  servos: [{id, pulse}, ...]
  """
  def set_servos(servos, duration \\ 0.5) do
    Connection.set_pwm_servo(duration, servos)
  end

  @doc """
  Center the gimbal.
  Servo 5 = tilt (up/down), Servo 6 = pan (left/right)
  """
  def center_gimbal do
    # Note: Pan center may need adjustment if physically off-center
    set_servos([{5, 1500}, {6, 1500}])
  end

  # ---- Motors ----
  #
  # Motor layout (top-down view):
  #   1 (FL) ---- 2 (FR)
  #      \      /
  #       \    /
  #       /    \
  #      /      \
  #   3 (RL) ---- 4 (RR)
  #
  # Motors 1 and 3 (left side) are inverted in hardware.
  # Mecanum wheels have rollers at 45° for omnidirectional movement.

  @doc """
  Set individual motor duty cycle.
  motor_id: 1-4
  duty: -100 to 100
  """
  def set_motor(motor_id, duty) do
    Connection.set_motor_duty([{motor_id, duty}])
  end

  @doc """
  Stop all motors.
  """
  def stop do
    emit_motor_telemetry(:stop, 0)
    Connection.set_motor_duty([{1, 0}, {2, 0}, {3, 0}, {4, 0}])
  end

  @doc """
  Drive using mecanum inverse kinematics with independent velocity vectors.

  This allows arbitrary movement combinations - forward while rotating,
  diagonal at any angle, etc. Motor outputs are automatically normalized
  so no wheel exceeds 100% duty.

  ## Parameters
    - vx: forward/backward velocity (-100 to 100, positive = forward)
    - vy: left/right strafe velocity (-100 to 100, positive = left)
    - omega: rotational velocity (-100 to 100, positive = clockwise/right)

  ## Examples
      # Pure forward
      Board.mecanum_drive(50, 0, 0)

      # Strafe left while moving forward
      Board.mecanum_drive(50, 50, 0)

      # Forward while rotating right
      Board.mecanum_drive(50, 0, 30)

      # Diagonal at 30° (more forward than strafe)
      Board.mecanum_drive(87, 50, 0)
  """
  def mecanum_drive(vx, vy, omega) do
    # Calculate effective speed for telemetry (magnitude of translation)
    effective_speed = round(:math.sqrt(vx * vx + vy * vy))
    emit_motor_telemetry(:mecanum, min(effective_speed, 100))
    do_mecanum_drive(vx, vy, omega)
  end

  # Internal mecanum drive without telemetry (used by drive/2 which emits its own)
  defp do_mecanum_drive(vx, vy, omega) do
    # Calculate raw motor duties using mecanum inverse kinematics
    # Formulas account for left motor inversion
    m1 = -vx + vy - omega
    m2 = vx + vy - omega
    m3 = -vx - vy - omega
    m4 = vx - vy - omega

    # Normalize if any motor exceeds 100% duty
    max_raw = Enum.max([abs(m1), abs(m2), abs(m3), abs(m4)])

    {m1, m2, m3, m4} =
      if max_raw > 100 do
        scale = 100 / max_raw
        {m1 * scale, m2 * scale, m3 * scale, m4 * scale}
      else
        {m1, m2, m3, m4}
      end

    Connection.set_motor_duty([
      {1, round(m1)},
      {2, round(m2)},
      {3, round(m3)},
      {4, round(m4)}
    ])
  end

  @doc """
  Drive in a cardinal direction at given speed.

  For more control, use `mecanum_drive/3` which allows arbitrary
  movement combinations.

  ## Directions
    - `:forward`, `:backward` - longitudinal movement
    - `:left`, `:right` - lateral strafing
    - `:rotate_left`, `:rotate_right` - rotation in place
    - `:forward_left`, `:forward_right` - 45° diagonal forward
    - `:backward_left`, `:backward_right` - 45° diagonal backward
  """
  def drive(direction, speed \\ 50)

  def drive(:forward, speed) do
    emit_motor_telemetry(:forward, speed)
    do_mecanum_drive(speed, 0, 0)
  end

  def drive(:backward, speed) do
    emit_motor_telemetry(:backward, speed)
    do_mecanum_drive(-speed, 0, 0)
  end

  def drive(:left, speed) do
    emit_motor_telemetry(:left, speed)
    do_mecanum_drive(0, speed, 0)
  end

  def drive(:right, speed) do
    emit_motor_telemetry(:right, speed)
    do_mecanum_drive(0, -speed, 0)
  end

  def drive(:rotate_left, speed) do
    emit_motor_telemetry(:rotate_left, speed)
    do_mecanum_drive(0, 0, -speed)
  end

  def drive(:rotate_right, speed) do
    emit_motor_telemetry(:rotate_right, speed)
    do_mecanum_drive(0, 0, speed)
  end

  def drive(:forward_left, speed) do
    emit_motor_telemetry(:forward_left, speed)
    do_mecanum_drive(speed, speed, 0)
  end

  def drive(:forward_right, speed) do
    emit_motor_telemetry(:forward_right, speed)
    do_mecanum_drive(speed, -speed, 0)
  end

  def drive(:backward_left, speed) do
    emit_motor_telemetry(:backward_left, speed)
    do_mecanum_drive(-speed, speed, 0)
  end

  def drive(:backward_right, speed) do
    emit_motor_telemetry(:backward_right, speed)
    do_mecanum_drive(-speed, -speed, 0)
  end

  defp emit_motor_telemetry(direction, speed) do
    :telemetry.execute(
      [:board, :motors, :command],
      %{direction: direction, speed: speed},
      %{}
    )
  end

  # ---- Buzzer ----

  @doc """
  Beep the buzzer.
  """
  def beep(freq \\ 1000, duration \\ 0.1) do
    # off_time must be > 0 or buzzer runs continuously
    Connection.set_buzzer(freq, duration, 0.1, 1)
  end

  @doc """
  Stop the buzzer.
  """
  def buzzer_off do
    Connection.set_buzzer(0, 0, 0, 0)
  end

  # ---- Battery ----

  @doc """
  Get the current battery voltage in millivolts.
  Returns {:ok, voltage_mv} or {:error, :no_data}.
  """
  def get_battery do
    Board.Battery.get_voltage()
  end

  # ---- Camera ----

  @doc """
  Start the camera stream.
  Stream will be available at http://192.168.0.90:5000/stream
  """
  def start_camera do
    Board.Camera.start_stream()
  end

  @doc """
  Stop the camera stream.
  """
  def stop_camera do
    Board.Camera.stop_stream()
  end

  @doc """
  Check if camera is streaming.
  """
  def camera_streaming? do
    Board.Camera.streaming?()
  end

  @doc """
  Get the camera stream URL.
  """
  def camera_stream_url do
    Board.Camera.stream_url()
  end

  # ---- Status ----

  @doc """
  Check if connected to the board.
  """
  def connected? do
    Connection.connected?()
  end
end
