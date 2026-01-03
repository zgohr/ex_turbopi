defmodule Board.LineFollower do
  @moduledoc """
  Controls the Hiwonder 4-channel IR line follower sensor.

  The sensor is at I2C address 0x48 on bus "i2c-1".

  ## Features
  - 4 IR sensors for line detection
  - Binary detection (line present or not per channel)
  - Suitable for line following, intersection detection, etc.

  ## Sensor Layout (front of robot)

      [1] [2] [3] [4]
       |   |   |   |
       v   v   v   v
      ---------------
          front

  Sensors are numbered 1-4 from left to right when facing forward.
  """
  use GenServer
  require Logger
  import Bitwise

  @i2c_bus "i2c-1"
  @i2c_addr 0x48

  # Register for reading sensor state
  @reg_state 0x01

  defstruct [:i2c_ref, :last_reading]

  # ---- Client API ----

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Read the current state of all 4 sensors.

  Returns `{:ok, [s1, s2, s3, s4]}` where each value is:
  - `true` - line detected (dark surface)
  - `false` - no line (light surface)

  Returns `{:error, reason}` if the sensor is not connected.

  ## Example

      {:ok, [false, true, true, false]} = Board.LineFollower.read()
      # Sensors 2 and 3 are over the line
  """
  def read do
    GenServer.call(__MODULE__, :read)
  end

  @doc """
  Check if the sensor is connected.
  """
  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  @doc """
  Get the last reading without triggering a new I2C read.
  Useful for high-frequency polling without blocking.
  """
  def get_last_reading do
    GenServer.call(__MODULE__, :get_last_reading)
  end

  # ---- Server Callbacks ----

  @impl true
  def init(_opts) do
    case open_i2c() do
      {:ok, i2c_ref} ->
        Logger.info(
          "Line follower connected on #{@i2c_bus} at address 0x#{Integer.to_string(@i2c_addr, 16)}"
        )

        {:ok, %__MODULE__{i2c_ref: i2c_ref, last_reading: [false, false, false, false]}}

      {:error, reason} ->
        Logger.warning(
          "Failed to open line follower I2C: #{inspect(reason)}, running in mock mode"
        )

        {:ok, %__MODULE__{i2c_ref: nil, last_reading: [false, false, false, false]}}
    end
  end

  @impl true
  def handle_call(:read, _from, %{i2c_ref: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:read, _from, %{i2c_ref: i2c_ref} = state) do
    case read_sensors(i2c_ref) do
      {:ok, sensors} ->
        {:reply, {:ok, sensors}, %{state | last_reading: sensors}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:connected?, _from, state) do
    {:reply, state.i2c_ref != nil, state}
  end

  def handle_call(:get_last_reading, _from, state) do
    {:reply, state.last_reading, state}
  end

  # ---- Private Functions ----

  defp open_i2c do
    with {:ok, ref} <- Circuits.I2C.open(@i2c_bus),
         {:ok, _} <- Circuits.I2C.read(ref, @i2c_addr, 1) do
      {:ok, ref}
    end
  end

  defp read_sensors(i2c_ref) do
    case Circuits.I2C.write_read(i2c_ref, @i2c_addr, <<@reg_state>>, 1) do
      {:ok, <<value>>} ->
        # Bits 0-3 represent sensors 1-4
        sensors = [
          (value &&& 0x01) > 0,
          (value &&& 0x02) > 0,
          (value &&& 0x04) > 0,
          (value &&& 0x08) > 0
        ]

        {:ok, sensors}

      {:error, reason} ->
        Logger.error("Failed to read line follower: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
