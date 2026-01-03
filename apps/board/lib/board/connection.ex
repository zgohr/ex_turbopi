defmodule Board.Connection do
  @moduledoc """
  GenServer managing the serial connection to the TurboPi controller board.
  """
  use GenServer
  require Logger

  alias Board.Protocol

  @default_device "/dev/ttyAMA0"
  @default_baudrate 1_000_000

  defstruct [:uart_pid, :buffer, :subscribers]

  # ---- Client API ----

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send raw packet data to the board.
  """
  def send_packet(packet) when is_binary(packet) do
    GenServer.cast(__MODULE__, {:send, packet})
  end

  @doc """
  Subscribe to incoming data for a specific function type.
  """
  def subscribe(function) do
    GenServer.call(__MODULE__, {:subscribe, function, self()})
  end

  @doc """
  Check if connected to the board.
  """
  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  # ---- High-level convenience functions ----

  def set_rgb(pixels), do: send_packet(Protocol.rgb_set(pixels))

  def set_pwm_servo(duration, positions) do
    send_packet(Protocol.pwm_servo_set_position(duration, positions))
  end

  def set_motor_duty(motors), do: send_packet(Protocol.motor_set_duty(motors))
  def set_motor_speed(motors), do: send_packet(Protocol.motor_set_speed(motors))

  def set_buzzer(freq, on_time, off_time, repeat \\ 1) do
    send_packet(Protocol.buzzer_set(freq, on_time, off_time, repeat))
  end

  def set_bus_servo(duration, positions) do
    send_packet(Protocol.bus_servo_set_position(duration, positions))
  end

  # ---- Server Callbacks ----

  @impl true
  def init(opts) do
    device = Keyword.get(opts, :device, @default_device)
    baudrate = Keyword.get(opts, :baudrate, @default_baudrate)

    case open_uart(device, baudrate) do
      {:ok, uart_pid} ->
        Logger.info("Board connected on #{device} at #{baudrate} baud")
        {:ok, %__MODULE__{uart_pid: uart_pid, buffer: <<>>, subscribers: %{}}}

      {:error, reason} ->
        Logger.warning("Failed to open #{device}: #{inspect(reason)}, running in mock mode")
        {:ok, %__MODULE__{uart_pid: nil, buffer: <<>>, subscribers: %{}}}
    end
  end

  @impl true
  def handle_cast({:send, packet}, %{uart_pid: nil} = state) do
    # Mock mode - just log
    Logger.debug("Mock send: #{inspect(packet, base: :hex)}")
    {:noreply, state}
  end

  def handle_cast({:send, packet}, %{uart_pid: uart_pid} = state) do
    Circuits.UART.write(uart_pid, packet)
    {:noreply, state}
  end

  @impl true
  def handle_call({:subscribe, function, pid}, _from, state) do
    subscribers = Map.update(state.subscribers, function, [pid], &[pid | &1])
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call(:connected?, _from, state) do
    {:reply, state.uart_pid != nil, state}
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:error, reason}}, state) do
    Logger.error("UART error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    buffer = state.buffer <> data
    {new_buffer, state} = process_buffer(buffer, state)
    {:noreply, %{state | buffer: new_buffer}}
  end

  # ---- Private Functions ----

  defp open_uart(device, baudrate) do
    with {:ok, uart_pid} <- Circuits.UART.start_link(),
         :ok <-
           Circuits.UART.open(uart_pid, device,
             speed: baudrate,
             data_bits: 8,
             stop_bits: 1,
             parity: :none,
             active: true
           ) do
      {:ok, uart_pid}
    end
  end

  defp process_buffer(buffer, state) do
    case Protocol.parse_packet(buffer) do
      {:ok, function, data, rest} ->
        notify_subscribers(function, data, state.subscribers)
        process_buffer(rest, state)

      {:incomplete, buffer} ->
        {buffer, state}

      {:error, reason} ->
        Logger.warning("Packet parse error: #{inspect(reason)}")
        # Skip a byte and try again
        <<_skip, rest::binary>> = buffer
        process_buffer(rest, state)
    end
  end

  defp notify_subscribers(function, data, subscribers) do
    case Map.get(subscribers, function, []) do
      [] -> :ok
      pids -> Enum.each(pids, &send(&1, {:board, function, data}))
    end
  end
end
