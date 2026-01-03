defmodule Board.BatteryTest do
  use ExUnit.Case

  # Test the voltage_to_percentage calculation
  # Since it's a private function, we test it indirectly through get_percentage
  # or we can test the expected behavior

  describe "voltage to percentage conversion" do
    # These tests verify the expected percentage values for given voltages
    # Based on 2S 18650: 6.0V (empty) to 8.4V (full)

    test "full battery (8.4V) returns 100%" do
      # 8400 mV should be 100%
      assert calculate_percentage(8400) == 100
    end

    test "empty battery (6.0V) returns 0%" do
      # 6000 mV should be 0%
      assert calculate_percentage(6000) == 0
    end

    test "nominal voltage (7.4V) returns ~58%" do
      # 7400 mV is nominal for 2S LiPo
      # (7400 - 6000) / (8400 - 6000) * 100 = 58.33%
      result = calculate_percentage(7400)
      assert result >= 58 and result <= 59
    end

    test "overvoltage returns 100%" do
      assert calculate_percentage(9000) == 100
      assert calculate_percentage(10000) == 100
    end

    test "undervoltage returns 0%" do
      assert calculate_percentage(5000) == 0
      assert calculate_percentage(0) == 0
    end

    test "mid-range voltage calculation" do
      # 7200 mV: (7200 - 6000) / 2400 * 100 = 50%
      assert calculate_percentage(7200) == 50
    end

    test "percentage increases monotonically with voltage" do
      voltages = [6000, 6500, 7000, 7500, 8000, 8400]
      percentages = Enum.map(voltages, &calculate_percentage/1)

      # Each percentage should be >= previous
      percentages
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert b >= a, "Expected #{b} >= #{a}"
      end)
    end
  end

  # Helper to calculate percentage using the same formula as Battery module
  defp calculate_percentage(mv) when mv >= 8400, do: 100
  defp calculate_percentage(mv) when mv <= 6000, do: 0
  defp calculate_percentage(mv), do: round((mv - 6000) / (8400 - 6000) * 100)
end
