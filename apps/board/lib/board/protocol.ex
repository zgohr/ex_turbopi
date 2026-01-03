defmodule Board.Protocol do
  @moduledoc """
  Serial protocol for communicating with the TurboPi controller board.

  Packet format: 0xAA 0x55 [Function] [Length] [Data...] [CRC8]
  """

  # Function codes
  @func_sys 0
  @func_led 1
  @func_buzzer 2
  @func_motor 3
  @func_pwm_servo 4
  @func_bus_servo 5
  @func_key 6
  @func_imu 7
  @func_gamepad 8
  @func_sbus 9
  @func_oled 10
  @func_rgb 11

  # CRC8 polynomial: 0x07 (x^8 + x^2 + x + 1)
  @crc8_poly 0x07

  # Generate CRC8 lookup table at compile time
  @crc8_table (for i <- 0..255 do
                 Enum.reduce(0..7, i, fn _, crc ->
                   if Bitwise.band(crc, 0x80) != 0 do
                     Bitwise.bxor(Bitwise.bsl(crc, 1), @crc8_poly) |> Bitwise.band(0xFF)
                   else
                     Bitwise.bsl(crc, 1) |> Bitwise.band(0xFF)
                   end
                 end)
               end)
              |> List.to_tuple()

  @doc """
  Calculate CRC8 checksum for data using polynomial 0x07.
  """
  def crc8(data) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(0, fn byte, crc ->
      elem(@crc8_table, Bitwise.bxor(crc, byte))
    end)
  end

  @doc """
  Build a packet for the given function and data.
  Returns binary ready to send over serial.
  """
  def build_packet(function, data) when is_binary(data) do
    payload = <<function::8, byte_size(data)::8, data::binary>>
    crc = crc8(payload)
    <<0xAA, 0x55, payload::binary, crc::8>>
  end

  # ---- PWM Servo Commands ----

  @doc """
  Build packet to set PWM servo positions.
  positions: [{servo_id, pulse_width}, ...]
  duration: time in seconds
  """
  def pwm_servo_set_position(duration, positions) when is_list(positions) do
    duration_ms = trunc(duration * 1000)
    servo_data = encode_items(positions, fn {id, pulse} -> <<id::8, pulse::little-16>> end)

    build_packet(
      @func_pwm_servo,
      <<0x01, duration_ms::little-16, length(positions)::8, servo_data::binary>>
    )
  end

  # ---- Motor Commands ----

  @doc """
  Build packet to set motor duty cycles.
  motors: [{motor_id, duty}, ...] where duty is -100 to 100
  """
  def motor_set_duty(motors) when is_list(motors) do
    motor_data = encode_items(motors, fn {id, duty} -> <<id - 1::8, duty::little-float-32>> end)
    build_packet(@func_motor, <<0x05, length(motors)::8, motor_data::binary>>)
  end

  @doc """
  Build packet to set motor speeds.
  motors: [{motor_id, speed}, ...]
  """
  def motor_set_speed(motors) when is_list(motors) do
    motor_data = encode_items(motors, fn {id, speed} -> <<id - 1::8, speed::little-float-32>> end)
    build_packet(@func_motor, <<0x01, length(motors)::8, motor_data::binary>>)
  end

  # ---- RGB LED Commands ----

  @doc """
  Build packet to set RGB LED colors.
  pixels: [{led_id, r, g, b}, ...]
  """
  def rgb_set(pixels) when is_list(pixels) do
    pixel_data = encode_items(pixels, fn {id, r, g, b} -> <<id - 1::8, r::8, g::8, b::8>> end)
    build_packet(@func_rgb, <<0x01, length(pixels)::8, pixel_data::binary>>)
  end

  # Helper to encode a list of items into binary
  defp encode_items(items, encoder_fn) do
    items |> Enum.map(encoder_fn) |> IO.iodata_to_binary()
  end

  # ---- Buzzer Commands ----

  @doc """
  Build packet to activate buzzer.
  freq: frequency in Hz
  on_time: on duration in seconds
  off_time: off duration in seconds
  repeat: number of repetitions
  """
  def buzzer_set(freq, on_time, off_time, repeat \\ 1) do
    on_ms = trunc(on_time * 1000)
    off_ms = trunc(off_time * 1000)
    data = <<freq::little-16, on_ms::little-16, off_ms::little-16, repeat::little-16>>
    build_packet(@func_buzzer, data)
  end

  # ---- Bus Servo Commands ----

  @doc """
  Build packet to set bus servo positions.
  positions: [{servo_id, position}, ...] where position is 0-1000
  duration: time in seconds
  """
  def bus_servo_set_position(duration, positions) when is_list(positions) do
    duration_ms = trunc(duration * 1000)
    servo_data = encode_items(positions, fn {id, pos} -> <<id::8, pos::little-16>> end)

    build_packet(
      @func_bus_servo,
      <<0x01, duration_ms::little-16, length(positions)::8, servo_data::binary>>
    )
  end

  # ---- Parsing Incoming Packets ----

  @doc """
  Parse incoming data, returning {function, data} tuples.
  Returns {:ok, function, data, rest} or {:incomplete, buffer} or {:error, reason}
  """
  def parse_packet(<<0xAA, 0x55, function::8, length::8, rest::binary>> = buffer) do
    # data + crc
    total_needed = length + 1

    if byte_size(rest) >= total_needed do
      <<data::binary-size(length), crc::8, remaining::binary>> = rest
      payload = <<function::8, length::8, data::binary>>

      if crc8(payload) == crc do
        {:ok, function, data, remaining}
      else
        {:error, :checksum_failed}
      end
    else
      {:incomplete, buffer}
    end
  end

  def parse_packet(<<0xAA, rest::binary>>) when byte_size(rest) < 3 do
    {:incomplete, <<0xAA, rest::binary>>}
  end

  def parse_packet(<<_byte, rest::binary>>) do
    # Skip invalid byte, try to find next packet
    parse_packet(rest)
  end

  def parse_packet(<<>>) do
    {:incomplete, <<>>}
  end

  # Function code accessors for pattern matching
  def func_sys, do: @func_sys
  def func_led, do: @func_led
  def func_buzzer, do: @func_buzzer
  def func_motor, do: @func_motor
  def func_pwm_servo, do: @func_pwm_servo
  def func_bus_servo, do: @func_bus_servo
  def func_key, do: @func_key
  def func_imu, do: @func_imu
  def func_gamepad, do: @func_gamepad
  def func_sbus, do: @func_sbus
  def func_oled, do: @func_oled
  def func_rgb, do: @func_rgb
end
