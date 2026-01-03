defmodule Board.ProtocolTest do
  use ExUnit.Case

  alias Board.Protocol

  describe "crc8/1" do
    test "calculates correct CRC for empty data" do
      assert Protocol.crc8(<<>>) == 0
    end

    test "calculates correct CRC for single byte" do
      # Known CRC8 values (using polynomial 0x07)
      assert Protocol.crc8(<<0x00>>) == 0
      assert Protocol.crc8(<<0x01>>) == 7
      # Verify actual computed value for 0xFF
      assert Protocol.crc8(<<0xFF>>) == 243
    end

    test "calculates correct CRC for multiple bytes" do
      # Test with known data - verify computed value
      crc = Protocol.crc8(<<0x01, 0x02, 0x03>>)
      # CRC should be deterministic
      assert crc == Protocol.crc8(<<0x01, 0x02, 0x03>>)
      assert is_integer(crc) and crc >= 0 and crc <= 255
    end

    test "different data produces different CRC" do
      crc1 = Protocol.crc8(<<1, 2, 3>>)
      crc2 = Protocol.crc8(<<1, 2, 4>>)
      assert crc1 != crc2
    end
  end

  describe "build_packet/2" do
    test "builds packet with correct header" do
      packet = Protocol.build_packet(0x01, <<0xAB>>)
      <<header::binary-size(2), _rest::binary>> = packet
      assert header == <<0xAA, 0x55>>
    end

    test "includes function code and length" do
      packet = Protocol.build_packet(0x05, <<1, 2, 3>>)
      <<0xAA, 0x55, function, length, _rest::binary>> = packet
      assert function == 0x05
      assert length == 3
    end

    test "appends CRC at end" do
      data = <<1, 2, 3>>
      packet = Protocol.build_packet(0x01, data)

      # Packet: header(2) + function(1) + length(1) + data(3) + crc(1) = 8 bytes
      assert byte_size(packet) == 8

      # Extract and verify CRC
      <<0xAA, 0x55, payload::binary-size(5), crc::8>> = packet
      expected_crc = Protocol.crc8(payload)
      assert crc == expected_crc
    end
  end

  describe "pwm_servo_set_position/2" do
    test "builds valid servo packet" do
      packet = Protocol.pwm_servo_set_position(0.5, [{5, 1500}])

      # Should start with header
      assert <<0xAA, 0x55, _rest::binary>> = packet
    end

    test "converts duration to milliseconds" do
      packet = Protocol.pwm_servo_set_position(1.0, [{1, 1000}])

      # Extract duration from packet
      # Header(2) + function(1) + length(1) + subcommand(1) + duration(2 LE)
      <<0xAA, 0x55, _func, _len, 0x01, duration::little-16, _rest::binary>> = packet
      assert duration == 1000
    end

    test "encodes multiple servos" do
      packet = Protocol.pwm_servo_set_position(0.5, [{5, 1500}, {6, 1200}])

      # Extract servo count
      <<0xAA, 0x55, _func, _len, 0x01, _duration::16, count, _rest::binary>> = packet
      assert count == 2
    end
  end

  describe "motor_set_duty/1" do
    test "builds valid motor packet" do
      packet = Protocol.motor_set_duty([{1, 50}])
      assert <<0xAA, 0x55, _rest::binary>> = packet
    end

    test "encodes motor ID as 0-indexed" do
      packet = Protocol.motor_set_duty([{1, 50.0}])

      # Extract motor ID (after header, func, len, subcommand, count)
      <<0xAA, 0x55, _func, _len, 0x05, _count, motor_id, _duty::binary>> = packet
      assert motor_id == 0
    end

    test "encodes duty as float32" do
      packet = Protocol.motor_set_duty([{1, 75.0}])

      # Extract duty value
      <<0xAA, 0x55, _func, _len, 0x05, _count, _id, duty::little-float-32, _crc>> = packet
      assert_in_delta duty, 75.0, 0.001
    end

    test "handles multiple motors" do
      packet = Protocol.motor_set_duty([{1, 50}, {2, -50}, {3, 0}, {4, 100}])

      <<0xAA, 0x55, _func, _len, 0x05, count, _rest::binary>> = packet
      assert count == 4
    end
  end

  describe "rgb_set/1" do
    test "builds valid RGB packet" do
      packet = Protocol.rgb_set([{1, 255, 0, 0}])
      assert <<0xAA, 0x55, _rest::binary>> = packet
    end

    test "encodes LED ID as 0-indexed" do
      packet = Protocol.rgb_set([{1, 255, 128, 64}])

      <<0xAA, 0x55, _func, _len, 0x01, _count, led_id, r, g, b, _crc>> = packet
      assert led_id == 0
      assert r == 255
      assert g == 128
      assert b == 64
    end

    test "handles multiple LEDs" do
      packet = Protocol.rgb_set([{1, 255, 0, 0}, {2, 0, 255, 0}])

      <<0xAA, 0x55, _func, _len, 0x01, count, _rest::binary>> = packet
      assert count == 2
    end
  end

  describe "buzzer_set/4" do
    test "builds valid buzzer packet" do
      packet = Protocol.buzzer_set(1000, 0.1, 0.1, 1)
      assert <<0xAA, 0x55, _rest::binary>> = packet
    end

    test "converts times to milliseconds" do
      packet = Protocol.buzzer_set(440, 0.5, 0.25, 3)

      <<0xAA, 0x55, _func, _len, freq::little-16, on_ms::little-16, off_ms::little-16,
        repeat::little-16, _crc>> = packet

      assert freq == 440
      assert on_ms == 500
      assert off_ms == 250
      assert repeat == 3
    end
  end

  describe "parse_packet/1" do
    test "parses valid packet" do
      # Build a packet and parse it back
      original_data = <<1, 2, 3>>
      packet = Protocol.build_packet(0x05, original_data)

      assert {:ok, function, data, rest} = Protocol.parse_packet(packet)
      assert function == 0x05
      assert data == original_data
      assert rest == <<>>
    end

    test "returns incomplete for partial packet" do
      assert {:incomplete, _} = Protocol.parse_packet(<<0xAA, 0x55>>)
      assert {:incomplete, _} = Protocol.parse_packet(<<0xAA, 0x55, 0x01>>)
    end

    test "returns incomplete for empty buffer" do
      assert {:incomplete, <<>>} = Protocol.parse_packet(<<>>)
    end

    test "skips invalid bytes to find packet" do
      # Garbage followed by valid packet
      garbage = <<0x00, 0x01, 0x02>>
      packet = Protocol.build_packet(0x01, <<0xAB>>)
      buffer = garbage <> packet

      assert {:ok, 0x01, <<0xAB>>, <<>>} = Protocol.parse_packet(buffer)
    end

    test "detects checksum failure" do
      # Build packet then corrupt the CRC
      packet = Protocol.build_packet(0x01, <<1, 2, 3>>)
      corrupted = binary_part(packet, 0, byte_size(packet) - 1) <> <<0xFF>>

      assert {:error, :checksum_failed} = Protocol.parse_packet(corrupted)
    end

    test "returns remaining data after packet" do
      packet = Protocol.build_packet(0x01, <<0xAB>>)
      trailing = <<0xDE, 0xAD, 0xBE, 0xEF>>
      buffer = packet <> trailing

      assert {:ok, 0x01, <<0xAB>>, ^trailing} = Protocol.parse_packet(buffer)
    end
  end

  describe "function code accessors" do
    test "returns correct function codes" do
      assert Protocol.func_sys() == 0
      assert Protocol.func_led() == 1
      assert Protocol.func_buzzer() == 2
      assert Protocol.func_motor() == 3
      assert Protocol.func_pwm_servo() == 4
      assert Protocol.func_bus_servo() == 5
      assert Protocol.func_key() == 6
      assert Protocol.func_imu() == 7
      assert Protocol.func_gamepad() == 8
      assert Protocol.func_sbus() == 9
      assert Protocol.func_oled() == 10
      assert Protocol.func_rgb() == 11
    end
  end
end
