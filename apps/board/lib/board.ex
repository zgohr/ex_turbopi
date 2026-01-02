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
  end

  @doc """
  Set both board RGB LEDs to the same color.
  The board has 2 LEDs (1 and 2).
  """
  def set_board_rgb(r, g, b) do
    Connection.set_rgb([{1, r, g, b}, {2, r, g, b}])
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
    Connection.set_motor_duty([{1, 0}, {2, 0}, {3, 0}, {4, 0}])
  end

  @doc """
  Drive in a direction.
  direction: :forward, :backward, :left, :right, :rotate_left, :rotate_right
  speed: 0-100
  """
  def drive(direction, speed \\ 50)

  # Motor mapping: 1=front-left(inv), 2=front-right, 3=back-left(inv), 4=back-right
  # Left side motors (1,3) are inverted, so negate their values

  def drive(:forward, speed) do
    Connection.set_motor_duty([{1, -speed}, {2, speed}, {3, -speed}, {4, speed}])
  end

  def drive(:backward, speed) do
    Connection.set_motor_duty([{1, speed}, {2, -speed}, {3, speed}, {4, -speed}])
  end

  def drive(:left, speed) do
    # Mecanum strafe left
    Connection.set_motor_duty([{1, speed}, {2, speed}, {3, -speed}, {4, -speed}])
  end

  def drive(:right, speed) do
    # Mecanum strafe right
    Connection.set_motor_duty([{1, -speed}, {2, -speed}, {3, speed}, {4, speed}])
  end

  def drive(:rotate_left, speed) do
    Connection.set_motor_duty([{1, speed}, {2, speed}, {3, speed}, {4, speed}])
  end

  def drive(:rotate_right, speed) do
    Connection.set_motor_duty([{1, -speed}, {2, -speed}, {3, -speed}, {4, -speed}])
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

  # ---- Status ----

  @doc """
  Check if connected to the board.
  """
  def connected? do
    Connection.connected?()
  end
end
