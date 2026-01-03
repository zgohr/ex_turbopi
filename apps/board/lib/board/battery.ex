defmodule Board.Battery do
  @moduledoc """
  Battery voltage monitoring.

  Subscribes to system packets from the TurboPi controller and parses
  battery voltage readings.

  ## Voltage Levels (2S 18650)
  - Full: ~8400 mV (4.2V per cell)
  - Nominal: ~7400 mV (3.7V per cell)
  - Low: ~6400 mV (3.2V per cell)
  - Critical: ~6000 mV (3.0V per cell)
  """
  use GenServer
  require Logger

  alias Board.Protocol

  @battery_subcommand 0x04

  defstruct [:voltage_mv]

  # ---- Client API ----

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current battery voltage in millivolts.
  Returns {:ok, voltage_mv} or {:error, :no_data}.
  """
  def get_voltage do
    GenServer.call(__MODULE__, :get_voltage)
  end

  @doc """
  Get battery percentage (approximate, based on 3S LiPo).
  Returns {:ok, 0-100} or {:error, :no_data}.
  """
  def get_percentage do
    case get_voltage() do
      {:ok, mv} -> {:ok, voltage_to_percentage(mv)}
      error -> error
    end
  end

  # ---- Server Callbacks ----

  @impl true
  def init(_opts) do
    # Subscribe to SYS packets from the connection
    Board.Connection.subscribe(Protocol.func_sys())

    {:ok, %__MODULE__{voltage_mv: nil}}
  end

  @impl true
  def handle_call(:get_voltage, _from, state) do
    result = if state.voltage_mv, do: {:ok, state.voltage_mv}, else: {:error, :no_data}
    {:reply, result, state}
  end

  @impl true
  def handle_info({:board, _function, data}, state) do
    case parse_sys_data(data) do
      {:battery, voltage_mv} ->
        # Emit telemetry event for power monitoring
        :telemetry.execute(
          [:board, :battery, :reading],
          %{voltage_mv: voltage_mv},
          %{}
        )

        {:noreply, %{state | voltage_mv: voltage_mv}}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ---- Private Functions ----

  defp parse_sys_data(<<@battery_subcommand, voltage::little-16>>) do
    {:battery, voltage}
  end

  defp parse_sys_data(<<subcommand, _rest::binary>>) do
    # Other SYS subcommands we don't handle yet
    Logger.debug("Unknown SYS subcommand: #{subcommand}")
    :unknown
  end

  defp parse_sys_data(_data) do
    :unknown
  end

  # Approximate percentage for 2S 18650 (6.0V - 8.4V range)
  # 2 cells × 3.0V empty = 6.0V, 2 cells × 4.2V full = 8.4V
  defp voltage_to_percentage(mv) when mv >= 8400, do: 100
  defp voltage_to_percentage(mv) when mv <= 6000, do: 0

  defp voltage_to_percentage(mv) do
    round((mv - 6000) / (8400 - 6000) * 100)
  end
end
