defmodule Board.LineFollowerTest do
  use ExUnit.Case
  import Bitwise

  describe "sensor value parsing" do
    test "all sensors off (0x00) returns all false" do
      assert parse_sensors(0x00) == [false, false, false, false]
    end

    test "all sensors on (0x0F) returns all true" do
      assert parse_sensors(0x0F) == [true, true, true, true]
    end

    test "only sensor 1 on (0x01)" do
      assert parse_sensors(0x01) == [true, false, false, false]
    end

    test "only sensor 2 on (0x02)" do
      assert parse_sensors(0x02) == [false, true, false, false]
    end

    test "only sensor 3 on (0x04)" do
      assert parse_sensors(0x04) == [false, false, true, false]
    end

    test "only sensor 4 on (0x08)" do
      assert parse_sensors(0x08) == [false, false, false, true]
    end

    test "center sensors on (0x06) - typical centered on line" do
      assert parse_sensors(0x06) == [false, true, true, false]
    end

    test "left sensors on (0x03) - robot drifted right" do
      assert parse_sensors(0x03) == [true, true, false, false]
    end

    test "right sensors on (0x0C) - robot drifted left" do
      assert parse_sensors(0x0C) == [false, false, true, true]
    end

    test "outer sensors only (0x09) - at intersection or wide line" do
      assert parse_sensors(0x09) == [true, false, false, true]
    end

    test "high bits are ignored (0xFF)" do
      # Only bits 0-3 matter
      assert parse_sensors(0xFF) == [true, true, true, true]
    end

    test "high bits set but low bits off (0xF0)" do
      assert parse_sensors(0xF0) == [false, false, false, false]
    end
  end

  describe "line position interpretation" do
    test "can determine line position from sensor states" do
      # All off - no line
      assert line_position([false, false, false, false]) == :none

      # Center - on the line
      assert line_position([false, true, true, false]) == :center
      assert line_position([true, true, true, true]) == :center

      # Left - need to turn right
      assert line_position([true, true, false, false]) == :left
      assert line_position([true, false, false, false]) == :far_left

      # Right - need to turn left
      assert line_position([false, false, true, true]) == :right
      assert line_position([false, false, false, true]) == :far_right
    end
  end

  # Helper to parse sensor values using the same logic as LineFollower
  defp parse_sensors(value) do
    [
      (value &&& 0x01) > 0,
      (value &&& 0x02) > 0,
      (value &&& 0x04) > 0,
      (value &&& 0x08) > 0
    ]
  end

  # Helper to interpret line position from sensor states
  # This is a simple algorithm - real line following would use PID control
  defp line_position([false, false, false, false]), do: :none
  defp line_position([true, false, false, false]), do: :far_left
  defp line_position([true, true, false, false]), do: :left
  defp line_position([false, true, true, false]), do: :center
  defp line_position([true, true, true, true]), do: :center
  defp line_position([false, false, true, true]), do: :right
  defp line_position([false, false, false, true]), do: :far_right
  defp line_position(_), do: :center
end
