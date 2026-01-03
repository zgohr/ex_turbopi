defmodule Board.Sonar do
  @moduledoc """
  Controls the Hiwonder I2C ultrasonic sensor with RGB LEDs.

  The sensor is at I2C address 0x77 on bus "i2c-1".

  ## Features
  - Distance measurement (0-5000mm)
  - 2 RGB LEDs with direct color control or breathing mode
  """
  use GenServer
  require Logger

  @i2c_bus "i2c-1"
  @i2c_addr 0x77

  # Register addresses
  @reg_distance 0x00
  @reg_rgb_mode 0x02
  @reg_rgb1_r 0x03
  @reg_rgb2_r 0x06

  defstruct [:i2c_ref, :pixels]

  # ---- Client API ----

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Set both sonar LEDs to the same RGB color.
  """
  def set_rgb(r, g, b) when r in 0..255 and g in 0..255 and b in 0..255 do
    GenServer.cast(__MODULE__, {:set_rgb, r, g, b})
    # Track state for persistence
    Board.LEDs.set(:sonar1, %{r: r, g: g, b: b})
    Board.LEDs.set(:sonar2, %{r: r, g: g, b: b})
  end

  @doc """
  Set a specific LED (0 or 1) to an RGB color.
  """
  def set_pixel(index, r, g, b)
      when index in [0, 1] and r in 0..255 and g in 0..255 and b in 0..255 do
    GenServer.cast(__MODULE__, {:set_pixel, index, r, g, b})
    # Track state for persistence
    led_key = String.to_atom("sonar#{index + 1}")
    Board.LEDs.set(led_key, %{r: r, g: g, b: b})
  end

  @doc """
  Get the distance reading in millimeters.
  Returns {:ok, distance_mm} or {:error, reason}.
  """
  def get_distance do
    GenServer.call(__MODULE__, :get_distance)
  end

  @doc """
  Turn off both LEDs.
  """
  def off do
    set_rgb(0, 0, 0)
  end

  @doc """
  Check if the sonar is connected.
  """
  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  @doc """
  Get current pixel colors as list of {r, g, b} tuples.
  """
  def get_pixels do
    GenServer.call(__MODULE__, :get_pixels)
  end

  # ---- Server Callbacks ----

  @impl true
  def init(_opts) do
    case open_i2c() do
      {:ok, i2c_ref} ->
        Logger.info(
          "Sonar connected on #{@i2c_bus} at address 0x#{Integer.to_string(@i2c_addr, 16)}"
        )

        # Set to direct RGB mode (not breathing)
        write_register(i2c_ref, @reg_rgb_mode, 0)
        {:ok, %__MODULE__{i2c_ref: i2c_ref, pixels: [{0, 0, 0}, {0, 0, 0}]}}

      {:error, reason} ->
        Logger.warning("Failed to open sonar I2C: #{inspect(reason)}, running in mock mode")
        {:ok, %__MODULE__{i2c_ref: nil, pixels: [{0, 0, 0}, {0, 0, 0}]}}
    end
  end

  @impl true
  def handle_cast({:set_rgb, r, g, b}, state) do
    state = set_pixel_internal(state, 0, r, g, b)
    state = set_pixel_internal(state, 1, r, g, b)
    {:noreply, state}
  end

  def handle_cast({:set_pixel, index, r, g, b}, state) do
    state = set_pixel_internal(state, index, r, g, b)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_distance, _from, %{i2c_ref: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:get_distance, _from, %{i2c_ref: i2c_ref} = state) do
    result = read_distance(i2c_ref)
    {:reply, result, state}
  end

  def handle_call(:connected?, _from, state) do
    {:reply, state.i2c_ref != nil, state}
  end

  def handle_call(:get_pixels, _from, state) do
    {:reply, state.pixels, state}
  end

  # ---- Private Functions ----

  defp open_i2c do
    case Circuits.I2C.open(@i2c_bus) do
      {:ok, ref} ->
        # Try a test read to verify the device is present
        case Circuits.I2C.read(ref, @i2c_addr, 1) do
          {:ok, _} -> {:ok, ref}
          {:error, reason} -> {:error, reason}
        end

      error ->
        error
    end
  end

  defp set_pixel_internal(%{i2c_ref: nil} = state, index, r, g, b) do
    Logger.debug("Mock sonar set_pixel(#{index}, #{r}, #{g}, #{b})")
    update_pixel(state, index, {r, g, b})
  end

  defp set_pixel_internal(%{i2c_ref: i2c_ref} = state, index, r, g, b) do
    base_reg = if index == 0, do: @reg_rgb1_r, else: @reg_rgb2_r

    with :ok <- write_register(i2c_ref, base_reg, r),
         :ok <- write_register(i2c_ref, base_reg + 1, g),
         :ok <- write_register(i2c_ref, base_reg + 2, b) do
      update_pixel(state, index, {r, g, b})
    else
      {:error, reason} ->
        Logger.error("Failed to set sonar pixel: #{inspect(reason)}")
        state
    end
  end

  defp update_pixel(state, index, color) do
    pixels = List.replace_at(state.pixels, index, color)
    %{state | pixels: pixels}
  end

  defp write_register(i2c_ref, register, value) do
    Circuits.I2C.write(i2c_ref, @i2c_addr, <<register, value>>)
  end

  defp read_distance(i2c_ref) do
    # Write the distance register address, then read 2 bytes
    with :ok <- Circuits.I2C.write(i2c_ref, @i2c_addr, <<@reg_distance>>),
         {:ok, <<low, high>>} <- Circuits.I2C.read(i2c_ref, @i2c_addr, 2) do
      distance = high * 256 + low
      # Cap at 5000mm like the Python SDK
      {:ok, min(distance, 5000)}
    end
  end
end
