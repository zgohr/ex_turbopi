defmodule Board.Telemetry do
  @moduledoc """
  Collects and aggregates telemetry data for power monitoring.

  Data is aggregated into 30-second windows, tracking:
  - Average/min/max voltage per window
  - Motor activity (% of time motors were running)
  - Camera activity (% of time camera was on)

  This provides meaningful trends over time to correlate power draw with voltage drops.
  """

  use GenServer
  require Logger

  @pubsub ExTurbopi.PubSub
  @topic "board:telemetry"

  # Aggregation settings
  # 30 seconds per data point
  @window_duration_ms 30_000
  # 20 windows = 10 minutes of history
  @max_history 20

  # Estimated current draw in mA (rough estimates)
  @camera_draw_ma 180
  # per motor at low speed
  @motor_base_draw_ma 50
  # per motor at full speed
  @motor_max_draw_ma 300

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current telemetry state.
  """
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Subscribe to telemetry updates.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Telemetry event handler - called by :telemetry.attach_many
  """
  def handle_event([:board, :battery, :reading], %{voltage_mv: voltage}, _metadata, _config) do
    GenServer.cast(__MODULE__, {:battery_reading, voltage})
  end

  def handle_event([:board, :camera, :state], %{streaming: streaming}, _metadata, _config) do
    GenServer.cast(__MODULE__, {:camera_state, streaming})
  end

  def handle_event([:board, :motors, :command], measurements, _metadata, _config) do
    GenServer.cast(__MODULE__, {:motor_command, measurements})
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  # Server Callbacks

  @impl true
  def init(_opts) do
    now = System.monotonic_time(:millisecond)

    state = %{
      # Completed 30s windows: [{timestamp, avg_voltage, motor_pct, camera_pct}, ...]
      history: [],
      # Current voltage reading (for live display)
      current_voltage: nil,
      # Current window data
      window: %{
        start_time: now,
        voltage_samples: [],
        motor_active_ms: 0,
        camera_active_ms: 0
      },
      # Real-time activity state
      active: %{
        camera: false,
        motors: false,
        motor_speed: 0
      },
      # For tracking activity duration
      last_motor_change: now,
      last_camera_change: now,
      last_motor_command: nil
    }

    # Schedule window finalization
    schedule_window_close()
    # Schedule motor idle check
    schedule_motor_idle_check()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, build_public_state(state), state}
  end

  @impl true
  def handle_cast({:battery_reading, voltage}, state) do
    # Add to current window's samples
    window = %{state.window | voltage_samples: [voltage | state.window.voltage_samples]}
    new_state = %{state | window: window, current_voltage: voltage}

    # Broadcast for live voltage display (not full state update)
    broadcast_update(new_state)

    {:noreply, new_state}
  end

  def handle_cast({:camera_state, streaming}, state) do
    now = System.monotonic_time(:millisecond)

    # Calculate time since last change and add to appropriate counter
    elapsed = now - state.last_camera_change

    window =
      if state.active.camera do
        %{state.window | camera_active_ms: state.window.camera_active_ms + elapsed}
      else
        state.window
      end

    new_state =
      state
      |> Map.put(:window, window)
      |> put_in([:active, :camera], streaming)
      |> Map.put(:last_camera_change, now)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_cast({:motor_command, %{direction: direction, speed: speed}}, state) do
    now = System.monotonic_time(:millisecond)
    was_active = state.active.motors
    is_active = direction != :stop and speed > 0

    # Calculate time motors were active since last change
    elapsed = now - state.last_motor_change

    window =
      if was_active do
        %{state.window | motor_active_ms: state.window.motor_active_ms + elapsed}
      else
        state.window
      end

    new_state =
      state
      |> Map.put(:window, window)
      |> put_in([:active, :motors], is_active)
      |> put_in([:active, :motor_speed], if(is_active, do: speed, else: 0))
      |> Map.put(:last_motor_change, now)
      |> Map.put(:last_motor_command, now)

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_cast({:motor_command, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:close_window, state) do
    now = System.monotonic_time(:millisecond)
    window_duration = now - state.window.start_time

    # Finalize any ongoing activity into the window
    motor_active_ms =
      if state.active.motors do
        state.window.motor_active_ms + (now - state.last_motor_change)
      else
        state.window.motor_active_ms
      end

    camera_active_ms =
      if state.active.camera do
        state.window.camera_active_ms + (now - state.last_camera_change)
      else
        state.window.camera_active_ms
      end

    # Calculate window stats
    window_entry =
      if length(state.window.voltage_samples) > 0 do
        avg_voltage =
          Enum.sum(state.window.voltage_samples) / length(state.window.voltage_samples)

        motor_pct = round(motor_active_ms / window_duration * 100)
        camera_pct = round(camera_active_ms / window_duration * 100)

        %{
          timestamp: System.system_time(:second),
          voltage: round(avg_voltage),
          motor_pct: motor_pct,
          camera_pct: camera_pct
        }
      else
        nil
      end

    # Add to history if we have data
    history =
      if window_entry do
        [window_entry | state.history] |> Enum.take(@max_history)
      else
        state.history
      end

    # Reset window
    new_state = %{
      state
      | history: history,
        window: %{
          start_time: now,
          voltage_samples: [],
          motor_active_ms: 0,
          camera_active_ms: 0
        },
        last_motor_change: now,
        last_camera_change: now
    }

    broadcast_update(new_state)
    schedule_window_close()
    {:noreply, new_state}
  end

  def handle_info(:check_motor_idle, state) do
    now = System.monotonic_time(:millisecond)

    # If no motor command in last 500ms, consider motors idle
    new_state =
      case state.last_motor_command do
        nil ->
          state

        last_time ->
          if now - last_time > 500 and state.active.motors do
            # Record the motor time before marking idle
            elapsed = now - state.last_motor_change

            window = %{
              state.window
              | motor_active_ms: state.window.motor_active_ms + elapsed
            }

            updated =
              state
              |> Map.put(:window, window)
              |> put_in([:active, :motors], false)
              |> put_in([:active, :motor_speed], 0)
              |> Map.put(:last_motor_change, now)

            broadcast_update(updated)
            updated
          else
            state
          end
      end

    schedule_motor_idle_check()
    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_window_close do
    Process.send_after(self(), :close_window, @window_duration_ms)
  end

  defp schedule_motor_idle_check do
    Process.send_after(self(), :check_motor_idle, 500)
  end

  defp broadcast_update(state) do
    # PubSub may not be started yet if Board starts before ExTurbopiWeb
    try do
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:telemetry_update, build_public_state(state)})
    rescue
      ArgumentError -> :ok
    end
  end

  defp build_public_state(state) do
    %{
      # For graph: list of %{timestamp, voltage, motor_pct, camera_pct}
      history: state.history,
      # Current voltage for live display
      current_voltage: state.current_voltage,
      # Current activity state
      active: state.active,
      # Estimated instantaneous draw
      estimated_draw: calculate_draw(state.active)
    }
  end

  defp calculate_draw(active) do
    camera_draw = if active.camera, do: @camera_draw_ma, else: 0

    motor_draw =
      if active.motors do
        # Scale motor draw based on speed (0-100)
        speed_factor = active.motor_speed / 100

        per_motor =
          @motor_base_draw_ma + (@motor_max_draw_ma - @motor_base_draw_ma) * speed_factor

        # 4 motors
        round(per_motor * 4)
      else
        0
      end

    %{
      camera: camera_draw,
      motors: motor_draw,
      total: camera_draw + motor_draw
    }
  end
end
