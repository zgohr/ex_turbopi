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

  # CRC8 lookup table (TurboPi board-specific, polynomial 0x31 reflected)
  @crc8_table {0, 94, 188, 226, 97, 63, 221, 131, 194, 156, 126, 32, 163, 253, 31, 65, 157, 195,
               33, 127, 252, 162, 64, 30, 95, 1, 227, 189, 62, 96, 130, 220, 35, 125, 159, 193,
               66, 28, 254, 160, 225, 191, 93, 3, 128, 222, 60, 98, 190, 224, 2, 92, 223, 129, 99,
               61, 124, 34, 192, 158, 29, 67, 161, 255, 70, 24, 250, 164, 39, 121, 155, 197, 132,
               218, 56, 102, 229, 187, 89, 7, 219, 133, 103, 57, 186, 228, 6, 88, 25, 71, 165,
               251, 120, 38, 196, 154, 101, 59, 217, 135, 4, 90, 184, 230, 167, 249, 27, 69, 198,
               152, 122, 36, 248, 166, 68, 26, 153, 199, 37, 123, 58, 100, 134, 216, 91, 5, 231,
               185, 140, 210, 48, 110, 237, 179, 81, 15, 78, 16, 242, 172, 47, 113, 147, 205, 17,
               79, 173, 243, 112, 46, 204, 146, 211, 141, 111, 49, 178, 236, 14, 80, 175, 241, 19,
               77, 206, 144, 114, 44, 109, 51, 209, 143, 12, 82, 176, 238, 50, 108, 142, 208, 83,
               13, 239, 177, 240, 174, 76, 18, 145, 207, 45, 115, 202, 148, 118, 40, 171, 245, 23,
               73, 8, 86, 180, 234, 105, 55, 213, 139, 87, 9, 235, 181, 54, 104, 138, 212, 149,
               203, 41, 119, 244, 170, 72, 22, 233, 183, 85, 11, 136, 214, 52, 106, 43, 117, 151,
               201, 74, 20, 246, 168, 116, 42, 200, 150, 21, 75, 169, 247, 182, 232, 10, 84, 215,
               137, 107, 53}

  @doc """
  Calculate CRC8 checksum for data.
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
