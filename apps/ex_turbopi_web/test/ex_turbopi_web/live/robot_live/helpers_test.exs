defmodule ExTurbopiWeb.RobotLive.HelpersTest do
  use ExUnit.Case, async: true

  alias ExTurbopiWeb.RobotLive.Helpers

  describe "voltage_chart_data/1" do
    test "returns nil for fewer than 2 data points" do
      assert Helpers.voltage_chart_data([]) == nil
      assert Helpers.voltage_chart_data([%{voltage: 7000}]) == nil
    end

    test "computes chart data for valid history" do
      history = [
        %{voltage: 7200, motor_pct: 10, camera_pct: 20},
        %{voltage: 7000, motor_pct: 15, camera_pct: 25}
      ]

      result = Helpers.voltage_chart_data(history)

      assert %{line: line, points: points, min_label: min_label, max_label: max_label} = result
      assert is_binary(line)
      assert length(points) == 2
      assert is_binary(min_label)
      assert is_binary(max_label)
    end
  end

  describe "voltage_range/1" do
    test "returns min and max with padding" do
      voltages = [7000, 7200, 7100]
      {min_v, max_v} = Helpers.voltage_range(voltages)

      # Min voltage is 7000, with 100mV padding = 6900
      # Range is 200 (7200-7000), but minimum is 200, so range = 200
      # Max = 7000 + 200 + 100 = 7300
      assert min_v == 6900
      assert max_v == 7300
    end

    test "ensures minimum 200mV range" do
      voltages = [7000, 7050]
      {min_v, max_v} = Helpers.voltage_range(voltages)

      # Range is 50mV, but minimum is 200mV
      # So: min = 7000 - 100 = 6900, max = 7000 + 200 + 100 = 7300
      assert max_v - min_v >= 200
    end
  end

  describe "key_velocity/4" do
    test "returns speed when positive key pressed" do
      keys = MapSet.new(["w"])
      assert Helpers.key_velocity(keys, "w", "s", 50) == 50
    end

    test "returns negative speed when negative key pressed" do
      keys = MapSet.new(["s"])
      assert Helpers.key_velocity(keys, "w", "s", 50) == -50
    end

    test "returns 0 when no relevant key pressed" do
      keys = MapSet.new(["a"])
      assert Helpers.key_velocity(keys, "w", "s", 50) == 0
    end

    test "returns 0 when positive key pressed but not allowed" do
      keys = MapSet.new(["w"])
      assert Helpers.key_velocity(keys, "w", "s", 50, false) == 0
    end

    test "prefers positive key when both pressed and allowed" do
      keys = MapSet.new(["w", "s"])
      assert Helpers.key_velocity(keys, "w", "s", 50) == 50
    end

    test "returns negative speed when both pressed but positive not allowed" do
      keys = MapSet.new(["w", "s"])
      assert Helpers.key_velocity(keys, "w", "s", 50, false) == -50
    end
  end

  describe "classify_movement/3" do
    test "returns nil when all velocities are zero" do
      assert Helpers.classify_movement(0, 0, 0) == nil
    end

    test "returns :rotate_right for positive omega only" do
      assert Helpers.classify_movement(0, 0, 50) == :rotate_right
    end

    test "returns :rotate_left for negative omega only" do
      assert Helpers.classify_movement(0, 0, -50) == :rotate_left
    end

    test "returns :forward for positive vx only" do
      assert Helpers.classify_movement(50, 0, 0) == :forward
    end

    test "returns :backward for negative vx only" do
      assert Helpers.classify_movement(-50, 0, 0) == :backward
    end

    test "returns :left for positive vy only" do
      assert Helpers.classify_movement(0, 50, 0) == :left
    end

    test "returns :right for negative vy only" do
      assert Helpers.classify_movement(0, -50, 0) == :right
    end

    test "returns :mecanum for combined movements" do
      assert Helpers.classify_movement(50, 50, 0) == :mecanum
      assert Helpers.classify_movement(50, 0, 50) == :mecanum
      assert Helpers.classify_movement(0, 50, 50) == :mecanum
      assert Helpers.classify_movement(50, 50, 50) == :mecanum
    end
  end

  describe "too_close?/1" do
    test "returns false for nil distance" do
      refute Helpers.too_close?(nil)
    end

    test "returns true when distance below threshold" do
      assert Helpers.too_close?(100)
      assert Helpers.too_close?(169)
    end

    test "returns false when distance at or above threshold" do
      refute Helpers.too_close?(170)
      refute Helpers.too_close?(500)
    end
  end

  describe "battery_color/1" do
    test "returns ghost for nil" do
      assert Helpers.battery_color(nil) == "badge-ghost"
    end

    test "returns success for high percentage" do
      assert Helpers.battery_color(100) == "badge-success"
      assert Helpers.battery_color(51) == "badge-success"
    end

    test "returns warning for medium percentage" do
      assert Helpers.battery_color(50) == "badge-warning"
      assert Helpers.battery_color(21) == "badge-warning"
    end

    test "returns error for low percentage" do
      assert Helpers.battery_color(20) == "badge-error"
      assert Helpers.battery_color(0) == "badge-error"
    end
  end

  describe "voltage_line_color/1" do
    test "returns dim color for nil" do
      assert Helpers.voltage_line_color(nil) == "text-base-content/50"
    end

    test "returns success for high voltage" do
      assert Helpers.voltage_line_color(8000) == "text-success"
      assert Helpers.voltage_line_color(7400) == "text-success"
    end

    test "returns warning for medium voltage" do
      assert Helpers.voltage_line_color(7399) == "text-warning"
      assert Helpers.voltage_line_color(6800) == "text-warning"
    end

    test "returns error for low voltage" do
      assert Helpers.voltage_line_color(6799) == "text-error"
      assert Helpers.voltage_line_color(6000) == "text-error"
    end
  end

  describe "distance_hud_class/1" do
    test "returns dim class for nil" do
      assert Helpers.distance_hud_class(nil) == "bg-black/50 text-white/50"
    end

    test "returns danger class for very close distance" do
      assert Helpers.distance_hud_class(100) == "bg-red-500/80 text-white"
      assert Helpers.distance_hud_class(149) == "bg-red-500/80 text-white"
    end

    test "returns warning class for close distance" do
      assert Helpers.distance_hud_class(150) == "bg-yellow-500/80 text-black"
      assert Helpers.distance_hud_class(299) == "bg-yellow-500/80 text-black"
    end

    test "returns safe class for far distance" do
      assert Helpers.distance_hud_class(300) == "bg-green-500/60 text-white"
      assert Helpers.distance_hud_class(1000) == "bg-green-500/60 text-white"
    end
  end

  describe "voltage_to_percentage/1" do
    test "returns 100 for full voltage" do
      assert Helpers.voltage_to_percentage(8400) == 100
      assert Helpers.voltage_to_percentage(9000) == 100
    end

    test "returns 0 for empty voltage" do
      assert Helpers.voltage_to_percentage(6000) == 0
      assert Helpers.voltage_to_percentage(5000) == 0
    end

    test "returns intermediate percentage" do
      # Mid-range: 6000 + (8400-6000)/2 = 7200
      assert Helpers.voltage_to_percentage(7200) == 50
    end
  end

  describe "format_distance/1" do
    test "formats distance in cm" do
      assert Helpers.format_distance(500) == "50.0 cm"
      assert Helpers.format_distance(155) == "15.5 cm"
    end

    test "truncates for large distances" do
      assert Helpers.format_distance(1000) == "100 cm"
      assert Helpers.format_distance(1500) == "150 cm"
    end
  end
end
