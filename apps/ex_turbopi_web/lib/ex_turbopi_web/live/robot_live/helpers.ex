defmodule ExTurbopiWeb.RobotLive.Helpers do
  @moduledoc """
  Pure helper functions for RobotLive UI calculations and classifications.
  Extracted for testability.
  """

  @min_safe_distance_mm 170

  # Chart calculations

  @doc """
  Computes voltage chart data from telemetry history.
  Returns nil if fewer than 2 data points.
  """
  def voltage_chart_data(history) when length(history) < 2, do: nil

  def voltage_chart_data(history) do
    voltages = Enum.map(history, & &1.voltage)
    {min_v, max_v} = voltage_range(voltages)
    step = 200 / max(length(history) - 1, 1)
    v_range = max(max_v - min_v, 1)

    points =
      history
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        x = idx * step
        y = 100 - (entry.voltage - min_v) / v_range * 80 - 10
        {Float.round(x, 1), Float.round(y, 1), entry.voltage}
      end)

    %{
      line: Enum.map_join(points, " ", fn {x, y, _v} -> "#{x},#{y}" end),
      points: points,
      min_label: "#{Float.round(min_v / 1000, 1)}V",
      max_label: "#{Float.round(max_v / 1000, 1)}V"
    }
  end

  @doc """
  Calculates voltage range with padding for chart display.
  Ensures at least 200mV range for readability.
  """
  def voltage_range(voltages) do
    min_v = Enum.min(voltages)
    max_v = Enum.max(voltages)
    range = max(max_v - min_v, 200)
    padding = 100
    {min_v - padding, min_v + range + padding}
  end

  # Movement classification

  @doc """
  Calculates velocity from key presses.
  Returns speed if pos_key pressed (and allowed), -speed if neg_key pressed, else 0.
  """
  def key_velocity(keys, pos_key, neg_key, speed, pos_allowed \\ true) do
    cond do
      MapSet.member?(keys, pos_key) and pos_allowed -> speed
      MapSet.member?(keys, neg_key) -> -speed
      true -> 0
    end
  end

  @doc """
  Classifies movement direction from velocity components.
  """
  def classify_movement(0, 0, 0), do: nil
  def classify_movement(0, 0, omega), do: if(omega > 0, do: :rotate_right, else: :rotate_left)
  def classify_movement(vx, 0, 0), do: if(vx > 0, do: :forward, else: :backward)
  def classify_movement(0, vy, 0), do: if(vy > 0, do: :left, else: :right)
  def classify_movement(_, _, _), do: :mecanum

  @doc """
  Checks if sonar distance is below safe threshold.
  """
  def too_close?(nil), do: false
  def too_close?(distance), do: distance < @min_safe_distance_mm

  # Status colors

  @doc "Returns badge class for battery percentage."
  def battery_color(nil), do: "badge-ghost"
  def battery_color(pct) when pct > 50, do: "badge-success"
  def battery_color(pct) when pct > 20, do: "badge-warning"
  def battery_color(_pct), do: "badge-error"

  @doc "Returns text class for voltage line."
  def voltage_line_color(nil), do: "text-base-content/50"
  def voltage_line_color(mv) when mv >= 7400, do: "text-success"
  def voltage_line_color(mv) when mv >= 6800, do: "text-warning"
  def voltage_line_color(_mv), do: "text-error"

  @doc "Returns HUD class for distance display."
  def distance_hud_class(nil), do: "bg-black/50 text-white/50"
  def distance_hud_class(mm) when mm < 150, do: "bg-red-500/80 text-white"
  def distance_hud_class(mm) when mm < 300, do: "bg-yellow-500/80 text-black"
  def distance_hud_class(_mm), do: "bg-green-500/60 text-white"

  # Conversions

  @doc "Converts battery voltage (mV) to percentage."
  def voltage_to_percentage(mv) when mv >= 8400, do: 100
  def voltage_to_percentage(mv) when mv <= 6000, do: 0
  def voltage_to_percentage(mv), do: round((mv - 6000) / (8400 - 6000) * 100)

  @doc "Formats distance in cm."
  def format_distance(mm) when mm >= 1000, do: "#{Float.round(mm / 10, 0) |> trunc()} cm"
  def format_distance(mm), do: "#{Float.round(mm / 10, 1)} cm"
end
