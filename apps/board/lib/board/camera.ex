defmodule Board.Camera do
  @moduledoc """
  Camera streaming control for TurboPi.

  Manages the Python MJPEG streaming server process.
  Stream is available at http://<pi_ip>:5000/stream when running.
  """

  use GenServer
  require Logger

  @camera_script "/home/pi/ex_turbopi_umbrella/scripts/camera_stream.py"
  @stream_port 5000
  @stream_host "192.168.0.90"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start the camera stream.
  Options:
    - width: frame width (default 320)
    - height: frame height (default 240)
  """
  def start_stream(opts \\ []) do
    GenServer.call(__MODULE__, {:start_stream, opts}, 10_000)
  end

  @doc """
  Stop the camera stream.
  """
  def stop_stream do
    GenServer.call(__MODULE__, :stop_stream)
  end

  @doc """
  Check if the camera is currently streaming.
  """
  def streaming? do
    GenServer.call(__MODULE__, :streaming?)
  end

  @doc """
  Get the stream URL.
  """
  def stream_url do
    "http://#{@stream_host}:#{@stream_port}/stream"
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      pid: nil,
      streaming: false,
      mock_mode: not hardware_available?()
    }

    if state.mock_mode do
      Logger.info("[Camera] Running in mock mode - no hardware available")
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:start_stream, _opts}, _from, %{streaming: true} = state) do
    {:reply, {:ok, :already_streaming}, state}
  end

  def handle_call({:start_stream, _opts}, _from, %{mock_mode: true} = state) do
    Logger.info("[Camera] Mock mode: simulating stream start")
    emit_camera_telemetry(true)
    {:reply, {:ok, :mock}, %{state | streaming: true}}
  end

  def handle_call({:start_stream, opts}, _from, state) do
    # Kill any existing camera process first
    kill_existing_camera()

    width = Keyword.get(opts, :width, 240)
    height = Keyword.get(opts, :height, 180)

    case start_camera_process(width, height) do
      {:ok, pid} ->
        Logger.info("[Camera] Stream started on port #{@stream_port} (#{width}x#{height})")
        emit_camera_telemetry(true)
        {:reply, :ok, %{state | pid: pid, streaming: true}}

      {:error, reason} = error ->
        Logger.error("[Camera] Failed to start stream: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:stop_stream, _from, %{streaming: false} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:stop_stream, _from, %{mock_mode: true} = state) do
    Logger.info("[Camera] Mock mode: simulating stream stop")
    emit_camera_telemetry(false)
    {:reply, :ok, %{state | streaming: false}}
  end

  def handle_call(:stop_stream, _from, %{pid: pid} = state) do
    stop_camera_process(pid)
    Logger.info("[Camera] Stream stopped")
    emit_camera_telemetry(false)
    {:reply, :ok, %{state | pid: nil, streaming: false}}
  end

  @impl true
  def handle_call(:streaming?, _from, state) do
    {:reply, state.streaming, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[Camera] Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{pid: pid}) when not is_nil(pid) do
    stop_camera_process(pid)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # Private Functions

  defp hardware_available? do
    File.exists?("/dev/video0") or File.exists?("/dev/video20")
  end

  defp kill_existing_camera do
    # Kill any existing camera_stream.py process
    System.cmd("pkill", ["-f", "camera_stream.py"], stderr_to_stdout: true)
    Process.sleep(500)
  end

  defp start_camera_process(width, height) do
    if File.exists?(@camera_script) do
      # Start the Python script as a detached background process
      # Using nohup to prevent it from dying when parent exits
      cmd =
        "nohup python3 #{@camera_script} --port #{@stream_port} --width #{width} --height #{height} > /tmp/camera_stream.log 2>&1 & echo $!"

      case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
        {output, 0} ->
          pid = String.trim(output) |> String.to_integer()
          Logger.debug("[Camera] Started process with PID #{pid}")

          # Wait for server to be ready
          if wait_for_server(5) do
            {:ok, pid}
          else
            # Server didn't start, kill the process
            System.cmd("kill", ["-9", Integer.to_string(pid)], stderr_to_stdout: true)
            {:error, :server_not_responding}
          end

        {output, code} ->
          Logger.error("[Camera] Failed to start: exit #{code}, output: #{output}")
          {:error, :failed_to_start}
      end
    else
      {:error, :script_not_found}
    end
  end

  defp wait_for_server(retries) when retries <= 0, do: false

  defp wait_for_server(retries) do
    Process.sleep(500)

    case System.cmd(
           "curl",
           [
             "-s",
             "-o",
             "/dev/null",
             "-w",
             "%{http_code}",
             "http://localhost:#{@stream_port}/status"
           ],
           stderr_to_stdout: true
         ) do
      {"200", 0} ->
        true

      _ ->
        wait_for_server(retries - 1)
    end
  end

  defp stop_camera_process(nil), do: :ok

  defp stop_camera_process(pid) when is_integer(pid) do
    # Send SIGTERM first
    System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
    Process.sleep(300)
    # Force kill
    System.cmd("kill", ["-9", Integer.to_string(pid)], stderr_to_stdout: true)
    # Also kill any other camera_stream processes
    System.cmd("pkill", ["-f", "camera_stream.py"], stderr_to_stdout: true)
    :ok
  end

  defp stop_camera_process(_), do: :ok

  defp emit_camera_telemetry(streaming) do
    :telemetry.execute(
      [:board, :camera, :state],
      %{streaming: streaming},
      %{}
    )
  end
end
