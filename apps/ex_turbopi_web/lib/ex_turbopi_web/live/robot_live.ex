defmodule ExTurbopiWeb.RobotLive do
  use ExTurbopiWeb, :live_view

  @default_pan 1500
  @default_tilt 1500
  # Pan range (left/right)
  @pan_min 800
  @pan_max 2200
  # Tilt range (up/down) - more limited
  @tilt_min 800
  @tilt_max 1890

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:connected, Board.connected?())
      |> assign(:pan, @default_pan)
      |> assign(:tilt, @default_tilt)
      |> assign(:pan_min, @pan_min)
      |> assign(:pan_max, @pan_max)
      |> assign(:tilt_min, @tilt_min)
      |> assign(:tilt_max, @tilt_max)
      |> assign(:leds, %{
        sonar1: %{r: 0, g: 0, b: 0},
        sonar2: %{r: 0, g: 0, b: 0},
        board1: %{r: 0, g: 0, b: 0},
        board2: %{r: 0, g: 0, b: 0}
      })
      |> assign(:speed, 50)
      |> assign(:moving, nil)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <.header>
          TurboPi Control
          <:subtitle>
            <span class={["badge", (@connected && "badge-success") || "badge-warning"]}>
              {if @connected, do: "Connected", else: "Mock Mode"}
            </span>
          </:subtitle>
        </.header>

        <%!-- Motor Controls --%>
        <div class="card bg-base-200 p-6">
          <h2 class="card-title mb-4">Drive</h2>
          <div class="flex flex-col items-center gap-2">
            <div class="flex gap-2">
              <button
                class="btn btn-lg btn-square"
                phx-click="drive"
                phx-value-direction="forward"
              >
                <.icon name="hero-arrow-up" class="size-6" />
              </button>
            </div>
            <div class="flex gap-2">
              <button
                class="btn btn-lg btn-square"
                phx-click="drive"
                phx-value-direction="left"
              >
                <.icon name="hero-arrow-left" class="size-6" />
              </button>
              <button class="btn btn-lg btn-square btn-error" phx-click="stop">
                <.icon name="hero-stop" class="size-6" />
              </button>
              <button
                class="btn btn-lg btn-square"
                phx-click="drive"
                phx-value-direction="right"
              >
                <.icon name="hero-arrow-right" class="size-6" />
              </button>
            </div>
            <div class="flex gap-2">
              <button
                class="btn btn-lg btn-square"
                phx-click="drive"
                phx-value-direction="backward"
              >
                <.icon name="hero-arrow-down" class="size-6" />
              </button>
            </div>
            <div class="flex gap-4 mt-4">
              <button
                class="btn btn-square"
                phx-click="drive"
                phx-value-direction="rotate_left"
              >
                <.icon name="hero-arrow-uturn-left" class="size-5" />
              </button>
              <button
                class="btn btn-square"
                phx-click="drive"
                phx-value-direction="rotate_right"
              >
                <.icon name="hero-arrow-uturn-right" class="size-5" />
              </button>
            </div>
            <div class="form-control w-full max-w-xs mt-4">
              <label class="label">
                <span class="label-text">Speed: {@speed}%</span>
              </label>
              <input
                type="range"
                min="10"
                max="100"
                value={@speed}
                class="range"
                phx-change="set_speed"
                name="speed"
              />
            </div>
          </div>
        </div>

        <%!-- Gimbal Controls --%>
        <div class="card bg-base-200 p-6">
          <h2 class="card-title mb-4">Gimbal</h2>
          <form phx-change="gimbal_change" id="gimbal-form">
            <div class="grid grid-cols-2 gap-6">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Pan: {@pan}</span>
                </label>
                <input
                  type="range"
                  min={@pan_min}
                  max={@pan_max}
                  value={@pan}
                  class="range"
                  name="pan"
                  phx-debounce="50"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Tilt: {@tilt}</span>
                </label>
                <input
                  type="range"
                  min={@tilt_min}
                  max={@tilt_max}
                  value={@tilt}
                  class="range"
                  name="tilt"
                  phx-debounce="50"
                />
              </div>
            </div>
          </form>
          <button class="btn btn-soft mt-4" phx-click="center_gimbal">
            Center Gimbal
          </button>
        </div>

        <%!-- RGB LEDs --%>
        <div class="card bg-base-200 p-6">
          <h2 class="card-title mb-4">RGB LEDs</h2>
          <div class="grid grid-cols-2 gap-4">
            <.led_control id="sonar1" label="Sonar 1" rgb={@leds.sonar1} />
            <.led_control id="sonar2" label="Sonar 2" rgb={@leds.sonar2} />
            <.led_control id="board1" label="Board 1" rgb={@leds.board1} />
            <.led_control id="board2" label="Board 2" rgb={@leds.board2} />
          </div>
        </div>

        <%!-- Buzzer --%>
        <div class="card bg-base-200 p-6">
          <h2 class="card-title mb-4">Buzzer</h2>
          <button class="btn btn-primary" phx-click="beep">
            <.icon name="hero-speaker-wave" class="size-5" /> Beep
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :rgb, :map, required: true

  defp led_control(assigns) do
    ~H"""
    <div class="bg-base-300 rounded-lg p-4">
      <div class="flex items-center gap-3 mb-3">
        <div style={"width: 40px; height: 40px; border-radius: 50%; background-color: rgb(#{@rgb.r}, #{@rgb.g}, #{@rgb.b}); border: 2px solid rgba(255,255,255,0.2);"}>
        </div>
        <span class="font-medium">{@label}</span>
      </div>
      <form phx-change="led_change" id={"led-form-#{@id}"} class="space-y-2">
        <input type="hidden" name="led" value={@id} />
        <div class="flex items-center gap-2">
          <span class="w-4 text-xs text-error">R</span>
          <input
            type="range"
            min="0"
            max="255"
            value={@rgb.r}
            class="range range-error range-xs flex-1"
            name="r"
            phx-debounce="50"
          />
        </div>
        <div class="flex items-center gap-2">
          <span class="w-4 text-xs text-success">G</span>
          <input
            type="range"
            min="0"
            max="255"
            value={@rgb.g}
            class="range range-success range-xs flex-1"
            name="g"
            phx-debounce="50"
          />
        </div>
        <div class="flex items-center gap-2">
          <span class="w-4 text-xs text-info">B</span>
          <input
            type="range"
            min="0"
            max="255"
            value={@rgb.b}
            class="range range-info range-xs flex-1"
            name="b"
            phx-debounce="50"
          />
        </div>
      </form>
      <div class="flex gap-1 mt-3">
        <button
          class="btn btn-xs btn-error"
          phx-click="led_preset"
          phx-value-led={@id}
          phx-value-color="red"
        >
          R
        </button>
        <button
          class="btn btn-xs btn-success"
          phx-click="led_preset"
          phx-value-led={@id}
          phx-value-color="green"
        >
          G
        </button>
        <button
          class="btn btn-xs btn-info"
          phx-click="led_preset"
          phx-value-led={@id}
          phx-value-color="blue"
        >
          B
        </button>
        <button
          class="btn btn-xs btn-warning"
          phx-click="led_preset"
          phx-value-led={@id}
          phx-value-color="yellow"
        >
          Y
        </button>
        <button class="btn btn-xs" phx-click="led_preset" phx-value-led={@id} phx-value-color="off">
          Off
        </button>
      </div>
    </div>
    """
  end

  def handle_event("drive", %{"direction" => direction}, socket) do
    direction = String.to_existing_atom(direction)
    Board.drive(direction, socket.assigns.speed)
    Process.send_after(self(), :auto_stop, 500)
    {:noreply, assign(socket, :moving, direction)}
  end

  def handle_event("stop", _params, socket) do
    Board.stop()
    {:noreply, assign(socket, :moving, nil)}
  end

  def handle_event("set_speed", %{"speed" => speed}, socket) do
    speed = String.to_integer(speed)
    {:noreply, assign(socket, :speed, speed)}
  end

  def handle_event("gimbal_change", %{"_target" => [target]} = params, socket) do
    socket =
      case target do
        "pan" ->
          pan = String.to_integer(params["pan"])
          Board.set_servo(6, pan)
          assign(socket, :pan, pan)

        "tilt" ->
          tilt = String.to_integer(params["tilt"])
          Board.set_servo(5, tilt)
          assign(socket, :tilt, tilt)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("center_gimbal", _params, socket) do
    Board.center_gimbal()
    {:noreply, socket |> assign(:pan, @default_pan) |> assign(:tilt, @default_tilt)}
  end

  def handle_event("led_change", %{"led" => led_id} = params, socket) do
    led_key = String.to_existing_atom(led_id)
    current = socket.assigns.leds[led_key]

    rgb =
      Enum.reduce(params, current, fn
        {"r", v}, acc -> %{acc | r: String.to_integer(v)}
        {"g", v}, acc -> %{acc | g: String.to_integer(v)}
        {"b", v}, acc -> %{acc | b: String.to_integer(v)}
        _, acc -> acc
      end)

    set_led(led_key, rgb)
    leds = Map.put(socket.assigns.leds, led_key, rgb)
    {:noreply, assign(socket, :leds, leds)}
  end

  def handle_event("led_preset", %{"led" => led_id, "color" => color}, socket) do
    led_key = String.to_existing_atom(led_id)

    rgb =
      case color do
        "red" -> %{r: 255, g: 0, b: 0}
        "green" -> %{r: 0, g: 255, b: 0}
        "blue" -> %{r: 0, g: 0, b: 255}
        "yellow" -> %{r: 255, g: 255, b: 0}
        "off" -> %{r: 0, g: 0, b: 0}
      end

    set_led(led_key, rgb)
    leds = Map.put(socket.assigns.leds, led_key, rgb)
    {:noreply, assign(socket, :leds, leds)}
  end

  def handle_event("beep", _params, socket) do
    Board.beep()
    {:noreply, socket}
  end

  def handle_info(:auto_stop, socket) do
    Board.stop()
    {:noreply, assign(socket, :moving, nil)}
  end

  # Send LED commands to the appropriate hardware
  defp set_led(:sonar1, %{r: r, g: g, b: b}), do: Board.Sonar.set_pixel(0, r, g, b)
  defp set_led(:sonar2, %{r: r, g: g, b: b}), do: Board.Sonar.set_pixel(1, r, g, b)
  defp set_led(:board1, %{r: r, g: g, b: b}), do: Board.set_rgb(1, r, g, b)
  defp set_led(:board2, %{r: r, g: g, b: b}), do: Board.set_rgb(2, r, g, b)
end
