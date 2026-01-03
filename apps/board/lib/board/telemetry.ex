defmodule Board.Telemetry do
  @moduledoc """
  Collects and aggregates telemetry data for power monitoring.

  Tracks:
  - Battery voltage history (last 5 minutes)
  - Active power consumers (camera, motors)

  Broadcasts updates via PubSub for LiveView subscriptions.
  """

  use GenServer
  require Logger

  @pubsub ExTurbopi.PubSub
  @topic "board:telemetry"
  # 60 readings at 5s interval = 5 minutes
  @max_history 60

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
    state = %{
      voltage_history: [],
      current_voltage: nil,
      active: %{
        camera: false,
        motors: false,
        motor_speed: 0
      },
      last_motor_command: nil
    }

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
    now = System.system_time(:second)

    # Add to history, keeping only last N readings
    history =
      [{now, voltage} | state.voltage_history]
      |> Enum.take(@max_history)

    new_state = %{state | voltage_history: history, current_voltage: voltage}
    broadcast_update(new_state)

    {:noreply, new_state}
  end

  def handle_cast({:camera_state, streaming}, state) do
    new_state = put_in(state, [:active, :camera], streaming)
    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_cast({:motor_command, %{direction: direction, speed: speed}}, state) do
    is_active = direction != :stop and speed > 0

    new_state =
      state
      |> put_in([:active, :motors], is_active)
      |> put_in([:active, :motor_speed], if(is_active, do: speed, else: 0))
      |> Map.put(:last_motor_command, System.monotonic_time(:millisecond))

    broadcast_update(new_state)
    {:noreply, new_state}
  end

  def handle_cast({:motor_command, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_motor_idle, state) do
    # If no motor command in last 500ms, consider motors idle
    new_state =
      case state.last_motor_command do
        nil ->
          state

        last_time ->
          now = System.monotonic_time(:millisecond)

          if now - last_time > 500 and state.active.motors do
            updated =
              state
              |> put_in([:active, :motors], false)
              |> put_in([:active, :motor_speed], 0)

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
      voltage_history: state.voltage_history,
      current_voltage: state.current_voltage,
      active: state.active,
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
