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
  # Gimbal step size for arrow key control
  @gimbal_step 50

  @battery_poll_interval 5000
  @sonar_poll_interval 100
  @min_safe_distance_mm 170

  # Physics constants
  @physics_tick_ms 50
  # speed units per tick when accelerating
  @acceleration 8
  # speed units per tick when coasting
  @friction 3
  # speed units per tick when braking
  @brake_decel 12
  # default max speed
  @default_max_speed 50

  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :poll_battery)
      send(self(), :poll_sonar)
      send(self(), :physics_tick)
      # Subscribe to telemetry updates
      Board.Telemetry.subscribe()
    end

    # Get initial telemetry state
    telemetry = Board.Telemetry.get_state()

    socket =
      socket
      |> assign(:connected, Board.connected?())
      |> assign(:pan, @default_pan)
      |> assign(:tilt, @default_tilt)
      |> assign(:pan_min, @pan_min)
      |> assign(:pan_max, @pan_max)
      |> assign(:tilt_min, @tilt_min)
      |> assign(:tilt_max, @tilt_max)
      |> assign(:gimbal_step, @gimbal_step)
      |> assign(:leds, Board.LEDs.get_all())
      |> assign(:max_speed, @default_max_speed)
      |> assign(:moving, nil)
      |> assign(:keys_pressed, MapSet.new())
      # Physics state
      # -100 to 100 (negative = backward)
      |> assign(:velocity, 0)
      # -1 = left, 0 = straight, 1 = right
      |> assign(:steering, 0)
      |> assign(:leds_expanded, false)
      |> assign(:battery_voltage, nil)
      |> assign(:battery_percentage, nil)
      |> assign(:camera_streaming, Board.camera_streaming?())
      |> assign(:camera_stream_url, Board.camera_stream_url())
      |> assign(:sonar_distance, nil)
      # Telemetry state (30s aggregated windows)
      |> assign(:telemetry_history, telemetry.history)
      |> assign(:power_active, telemetry.active)
      |> assign(:power_draw, telemetry.estimated_draw)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        class="space-y-6"
        id="robot-control"
        phx-hook="KeyboardControls"
        phx-window-keydown="keydown"
        phx-window-keyup="keyup"
      >
        <%!-- Header with status --%>
        <div class="flex items-center justify-between flex-wrap gap-2">
          <h1 class="text-2xl font-bold">TurboPi</h1>
          <div class="flex items-center gap-3">
            <span class={["badge badge-sm", (@connected && "badge-success") || "badge-warning"]}>
              {if @connected, do: "Connected", else: "Mock"}
            </span>
            <.battery_indicator voltage={@battery_voltage} percentage={@battery_percentage} />
          </div>
        </div>

        <%!-- Camera with overlay controls --%>
        <div class="card bg-base-200 p-4">
          <div class="flex items-center justify-between mb-3">
            <div class="flex items-center gap-3">
              <button
                class={["btn btn-sm", (@camera_streaming && "btn-error") || "btn-success"]}
                phx-click={if @camera_streaming, do: "stop_camera", else: "start_camera"}
              >
                <.icon
                  name={if @camera_streaming, do: "hero-stop", else: "hero-video-camera"}
                  class="size-4"
                />
                {if @camera_streaming, do: "Stop", else: "Start"}
              </button>
              <span class="text-sm text-base-content/60">
                {if @camera_streaming, do: "WASD: drive | Arrows: gimbal", else: ""}
              </span>
            </div>
            <form phx-change="set_max_speed" class="flex items-center gap-2">
              <span class="text-sm">Max:</span>
              <input
                type="range"
                min="10"
                max="100"
                value={@max_speed}
                class="range range-xs w-24"
                name="max_speed"
              />
              <span class="text-sm w-8">{@max_speed}%</span>
            </form>
          </div>

          <%!-- Camera view with overlay --%>
          <div class="relative aspect-video bg-black rounded-lg overflow-hidden">
            <%= if @camera_streaming do %>
              <img
                src={@camera_stream_url}
                class="w-full h-full object-contain"
                alt="Camera stream"
              />
            <% else %>
              <div class="absolute inset-0 flex items-center justify-center">
                <span class="text-white/50">Camera off</span>
              </div>
            <% end %>

            <%!-- Distance HUD --%>
            <div class="absolute top-3 left-1/2 -translate-x-1/2 pointer-events-none z-10">
              <div class={[
                "px-3 py-1 rounded-full backdrop-blur font-mono text-sm font-bold shadow-lg",
                distance_hud_class(@sonar_distance)
              ]}>
                <%= if @sonar_distance do %>
                  <span class="opacity-70">▼</span>
                  {format_distance(@sonar_distance)}
                <% else %>
                  <span class="opacity-50">-- cm</span>
                <% end %>
              </div>
            </div>

            <%!-- Touch overlay controls --%>
            <div class="absolute inset-0 pointer-events-none">
              <%!-- Drive controls (left side) --%>
              <div class="absolute left-4 bottom-4 pointer-events-auto touch-manipulation">
                <div class="flex flex-col items-center gap-1">
                  <button
                    class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                    phx-click="drive"
                    phx-value-direction="forward"
                  >
                    <span class="text-white font-bold">W</span>
                  </button>
                  <div class="flex gap-1">
                    <button
                      class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                      phx-click="drive"
                      phx-value-direction="left"
                    >
                      <span class="text-white font-bold">A</span>
                    </button>
                    <button
                      class="btn btn-circle btn-sm btn-error bg-error/60 hover:bg-error/80 backdrop-blur"
                      phx-click="stop"
                    >
                      <.icon name="hero-stop" class="size-4 text-white" />
                    </button>
                    <button
                      class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                      phx-click="drive"
                      phx-value-direction="right"
                    >
                      <span class="text-white font-bold">D</span>
                    </button>
                  </div>
                  <button
                    class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                    phx-click="drive"
                    phx-value-direction="backward"
                  >
                    <span class="text-white font-bold">S</span>
                  </button>
                </div>
              </div>

              <%!-- Rotate controls (bottom center) --%>
              <div class="absolute bottom-4 left-1/2 -translate-x-1/2 pointer-events-auto touch-manipulation">
                <div class="flex gap-2">
                  <button
                    class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                    phx-click="drive"
                    phx-value-direction="rotate_left"
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-4 text-white" />
                  </button>
                  <button
                    class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                    phx-click="drive"
                    phx-value-direction="rotate_right"
                  >
                    <.icon name="hero-arrow-uturn-right" class="size-4 text-white" />
                  </button>
                </div>
              </div>

              <%!-- Gimbal controls (right side) --%>
              <div class="absolute right-4 bottom-4 pointer-events-auto touch-manipulation">
                <div class="flex flex-col items-center gap-1">
                  <button
                    class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                    phx-click="gimbal_step"
                    phx-value-direction="up"
                  >
                    <.icon name="hero-chevron-up" class="size-4 text-white" />
                  </button>
                  <div class="flex gap-1">
                    <button
                      class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                      phx-click="gimbal_step"
                      phx-value-direction="left"
                    >
                      <.icon name="hero-chevron-left" class="size-4 text-white" />
                    </button>
                    <button
                      class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                      phx-click="center_gimbal"
                    >
                      <.icon name="hero-arrows-pointing-in" class="size-4 text-white" />
                    </button>
                    <button
                      class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                      phx-click="gimbal_step"
                      phx-value-direction="right"
                    >
                      <.icon name="hero-chevron-right" class="size-4 text-white" />
                    </button>
                  </div>
                  <button
                    class="btn btn-circle btn-sm btn-ghost bg-white/20 hover:bg-white/40 backdrop-blur"
                    phx-click="gimbal_step"
                    phx-value-direction="down"
                  >
                    <.icon name="hero-chevron-down" class="size-4 text-white" />
                  </button>
                </div>
              </div>

              <%!-- Active indicator --%>
              <%= if @moving do %>
                <div class="absolute top-4 left-4 pointer-events-none">
                  <span class="badge badge-success badge-sm animate-pulse">
                    {String.upcase(to_string(@moving))}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Power Monitor --%>
        <.power_monitor
          history={@telemetry_history}
          current_voltage={@battery_voltage}
          active={@power_active}
          draw={@power_draw}
        />

        <%!-- Collapsible sections --%>
        <div class="collapse collapse-arrow bg-base-200">
          <input type="checkbox" id="led-toggle" phx-update="ignore" />
          <div class="collapse-title font-medium">RGB LEDs</div>
          <div class="collapse-content">
            <div class="grid grid-cols-2 gap-4 pt-2">
              <.led_control id="sonar1" label="Sonar 1" rgb={@leds.sonar1} />
              <.led_control id="sonar2" label="Sonar 2" rgb={@leds.sonar2} />
              <.led_control id="board1" label="Board 1" rgb={@leds.board1} />
              <.led_control id="board2" label="Board 2" rgb={@leds.board2} />
            </div>
          </div>
        </div>

        <div class="flex gap-4">
          <button class="btn btn-primary flex-1" phx-click="beep">
            <.icon name="hero-speaker-wave" class="size-5" /> Beep
          </button>
          <button class="btn btn-soft flex-1" phx-click="center_gimbal">
            Center Gimbal
          </button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :voltage, :integer, default: nil
  attr :percentage, :integer, default: nil

  defp battery_indicator(assigns) do
    ~H"""
    <div class={["badge badge-sm gap-1", battery_color(@percentage)]}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-3 w-3"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M17 8V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-2m2-4h.01M21 12a2 2 0 01-2 2h-2v-4h2a2 2 0 012 2z"
        />
      </svg>
      <%= if @voltage do %>
        {Float.round(@voltage / 1000, 1)}V
      <% else %>
        --
      <% end %>
    </div>
    """
  end

  defp battery_color(nil), do: "badge-ghost"
  defp battery_color(pct) when pct > 50, do: "badge-success"
  defp battery_color(pct) when pct > 20, do: "badge-warning"
  defp battery_color(_pct), do: "badge-error"

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :rgb, :map, required: true

  defp led_control(assigns) do
    ~H"""
    <div class="bg-base-300 rounded-lg p-3">
      <div class="flex items-center gap-2 mb-2">
        <div style={"width: 24px; height: 24px; border-radius: 50%; background-color: rgb(#{@rgb.r}, #{@rgb.g}, #{@rgb.b}); border: 2px solid rgba(255,255,255,0.2);"}>
        </div>
        <span class="text-sm font-medium">{@label}</span>
      </div>
      <div class="flex gap-1">
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

  attr :history, :list, default: []
  attr :current_voltage, :integer, default: nil
  attr :active, :map, default: %{camera: false, motors: false, motor_speed: 0}
  attr :draw, :map, default: %{camera: 0, motors: 0, total: 0}

  defp power_monitor(assigns) do
    ~H"""
    <div class="card bg-base-200 p-4">
      <div class="flex items-center justify-between mb-3">
        <h3 class="font-medium">Power Monitor</h3>
        <span class="text-xs text-base-content/50">30s intervals • 10min history</span>
      </div>

      <%!-- Active consumers with estimated draw --%>
      <div class="flex flex-wrap gap-4 text-sm mb-3">
        <div class={["flex items-center gap-1", @active.camera && "text-info"]}>
          <.icon name="hero-video-camera" class="size-4" />
          <span>Camera</span>
          <span class="text-xs opacity-70">
            {if @active.camera, do: "~#{@draw.camera}mA", else: "off"}
          </span>
        </div>
        <div class={["flex items-center gap-1", @active.motors && "text-warning"]}>
          <.icon name="hero-cog-6-tooth" class="size-4" />
          <span>Motors</span>
          <span class="text-xs opacity-70">
            {if @active.motors, do: "~#{@draw.motors}mA", else: "idle"}
          </span>
        </div>
        <%= if @draw.total > 0 do %>
          <div class="flex items-center gap-1 text-error">
            <.icon name="hero-bolt" class="size-4" />
            <span>~{@draw.total}mA</span>
          </div>
        <% end %>
      </div>

      <%!-- Main chart area --%>
      <div class="bg-base-300 rounded p-2">
        <%= if length(@history) >= 2 do %>
          <div class="h-24 relative">
            <svg viewBox="0 0 200 100" preserveAspectRatio="none" class="w-full h-full">
              <%!-- Activity bars (bottom layer) --%>
              <%= for {entry, idx} <- Enum.with_index(Enum.reverse(@history)) do %>
                <% bar_width = 200 / max(length(@history), 1) %>
                <% x = idx * bar_width %>
                <%!-- Motor activity bar (orange) --%>
                <rect
                  x={x}
                  y={100 - entry.motor_pct}
                  width={bar_width - 1}
                  height={entry.motor_pct}
                  class="fill-warning/40"
                />
                <%!-- Camera activity bar (blue, stacked) --%>
                <rect
                  x={x}
                  y={100 - entry.motor_pct - entry.camera_pct}
                  width={bar_width - 1}
                  height={entry.camera_pct}
                  class="fill-info/40"
                />
              <% end %>

              <%!-- Voltage line (top layer) --%>
              <polyline
                points={voltage_line(@history)}
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                class={voltage_line_color(@current_voltage)}
              />

              <%!-- Voltage dots --%>
              <%= for {entry, idx} <- Enum.with_index(Enum.reverse(@history)) do %>
                <% {_x, y} = voltage_point(@history, idx) %>
                <circle
                  cx={idx * (200 / max(length(@history) - 1, 1))}
                  cy={y}
                  r="3"
                  class={"fill-current " <> voltage_line_color(entry.voltage)}
                />
              <% end %>
            </svg>

            <%!-- Y-axis labels --%>
            <div class="absolute left-0 top-0 bottom-0 flex flex-col justify-between text-xs text-base-content/50 -ml-1 pointer-events-none">
              <span>{format_voltage_label(@history, :max)}</span>
              <span>{format_voltage_label(@history, :min)}</span>
            </div>

            <%!-- 100% activity line --%>
            <div class="absolute right-0 top-0 text-xs text-base-content/30">100%</div>
          </div>

          <%!-- Legend and time axis --%>
          <div class="flex justify-between items-center mt-2 text-xs">
            <div class="flex gap-3 text-base-content/60">
              <span class="flex items-center gap-1">
                <span class="w-3 h-2 bg-warning/40 rounded-sm"></span> Motors
              </span>
              <span class="flex items-center gap-1">
                <span class="w-3 h-2 bg-info/40 rounded-sm"></span> Camera
              </span>
              <span class="flex items-center gap-1">
                <span class="w-3 h-0.5 bg-success rounded"></span> Voltage
              </span>
            </div>
            <span class="text-base-content/50">
              <%= if @current_voltage do %>
                {Float.round(@current_voltage / 1000, 2)}V
              <% else %>
                --
              <% end %>
            </span>
          </div>
        <% else %>
          <div class="h-24 flex items-center justify-center text-base-content/30 text-sm">
            <div class="text-center">
              <div>Collecting data...</div>
              <div class="text-xs mt-1">First point in ~30s</div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp voltage_line(history) when length(history) < 2, do: ""

  defp voltage_line(history) do
    voltages = Enum.map(history, & &1.voltage)
    {min_v, max_v} = voltage_range(voltages)

    history
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {entry, idx} ->
      x = idx * (200 / max(length(history) - 1, 1))
      y = 100 - (entry.voltage - min_v) / max(max_v - min_v, 1) * 80 - 10
      "#{Float.round(x, 1)},#{Float.round(y, 1)}"
    end)
    |> Enum.join(" ")
  end

  defp voltage_point(history, idx) do
    voltages = Enum.map(history, & &1.voltage)
    {min_v, max_v} = voltage_range(voltages)
    entry = Enum.at(Enum.reverse(history), idx)
    x = idx * (200 / max(length(history) - 1, 1))
    y = 100 - (entry.voltage - min_v) / max(max_v - min_v, 1) * 80 - 10
    {x, y}
  end

  defp voltage_range(voltages) do
    min_v = Enum.min(voltages)
    max_v = Enum.max(voltages)
    # Ensure at least 200mV range for readability
    range = max(max_v - min_v, 200)
    padding = 100
    {min_v - padding, min_v + range + padding}
  end

  defp format_voltage_label(history, :max) do
    voltages = Enum.map(history, & &1.voltage)
    {_min_v, max_v} = voltage_range(voltages)
    "#{Float.round(max_v / 1000, 1)}V"
  end

  defp format_voltage_label(history, :min) do
    voltages = Enum.map(history, & &1.voltage)
    {min_v, _max_v} = voltage_range(voltages)
    "#{Float.round(min_v / 1000, 1)}V"
  end

  defp voltage_line_color(nil), do: "text-base-content/50"
  defp voltage_line_color(mv) when mv >= 7400, do: "text-success"
  defp voltage_line_color(mv) when mv >= 6800, do: "text-warning"
  defp voltage_line_color(_mv), do: "text-error"

  # Keyboard controls - track pressed keys for combined movement
  def handle_event("keydown", %{"key" => key}, socket) do
    key = String.downcase(key)

    # Handle gimbal separately (not tracked in keys_pressed)
    socket =
      case key do
        "arrowup" ->
          gimbal_step(:up, socket)

        "arrowdown" ->
          gimbal_step(:down, socket)

        "arrowleft" ->
          gimbal_step(:left, socket)

        "arrowright" ->
          gimbal_step(:right, socket)

        " " ->
          Board.stop()

          socket
          |> assign(:moving, nil)
          |> assign(:keys_pressed, MapSet.new())
          |> assign(:velocity, 0)
          |> assign(:steering, 0)

        k when k in ["w", "s", "a", "d", "q", "e"] ->
          keys = MapSet.put(socket.assigns.keys_pressed, k)

          socket
          |> assign(:keys_pressed, keys)
          |> update_drive_from_keys()

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("keyup", %{"key" => key}, socket) do
    key = String.downcase(key)

    socket =
      if key in ["w", "s", "a", "d", "q", "e"] do
        keys = MapSet.delete(socket.assigns.keys_pressed, key)

        socket
        |> assign(:keys_pressed, keys)
        |> update_drive_from_keys()
      else
        socket
      end

    {:noreply, socket}
  end

  # Touch/click controls
  def handle_event("drive", %{"direction" => direction}, socket) do
    direction = String.to_existing_atom(direction)
    Board.drive(direction, socket.assigns.max_speed)
    Process.send_after(self(), :auto_stop, 500)
    {:noreply, assign(socket, :moving, direction)}
  end

  def handle_event("stop", _params, socket) do
    Board.stop()
    {:noreply, assign(socket, :moving, nil)}
  end

  def handle_event("set_max_speed", %{"max_speed" => max_speed}, socket) do
    max_speed = String.to_integer(max_speed)
    {:noreply, assign(socket, :max_speed, max_speed)}
  end

  def handle_event("gimbal_step", %{"direction" => direction}, socket) do
    direction = String.to_existing_atom(direction)
    {:noreply, gimbal_step(direction, socket)}
  end

  def handle_event("center_gimbal", _params, socket) do
    Board.center_gimbal()
    {:noreply, socket |> assign(:pan, @default_pan) |> assign(:tilt, @default_tilt)}
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

  def handle_event("toggle_leds", _params, socket) do
    {:noreply, assign(socket, :leds_expanded, !socket.assigns.leds_expanded)}
  end

  def handle_event("start_camera", _params, socket) do
    case Board.start_camera() do
      :ok ->
        {:noreply, assign(socket, :camera_streaming, true)}

      {:ok, _} ->
        {:noreply, assign(socket, :camera_streaming, true)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start camera: #{inspect(reason)}")}
    end
  end

  def handle_event("stop_camera", _params, socket) do
    Board.stop_camera()
    {:noreply, assign(socket, :camera_streaming, false)}
  end

  def handle_info(:auto_stop, socket) do
    Board.stop()
    {:noreply, assign(socket, :moving, nil)}
  end

  def handle_info({:telemetry_update, telemetry}, socket) do
    socket =
      socket
      |> assign(:telemetry_history, telemetry.history)
      |> assign(:power_active, telemetry.active)
      |> assign(:power_draw, telemetry.estimated_draw)

    {:noreply, socket}
  end

  def handle_info(:poll_battery, socket) do
    socket =
      case Board.get_battery() do
        {:ok, voltage} ->
          percentage = voltage_to_percentage(voltage)
          assign(socket, battery_voltage: voltage, battery_percentage: percentage)

        {:error, _} ->
          socket
      end

    Process.send_after(self(), :poll_battery, @battery_poll_interval)
    {:noreply, socket}
  end

  def handle_info(:poll_sonar, socket) do
    socket =
      case Board.Sonar.get_distance() do
        {:ok, distance} ->
          socket = assign(socket, :sonar_distance, distance)

          # Auto-stop if moving forward and too close
          if socket.assigns.velocity > 0 and distance < @min_safe_distance_mm do
            Board.stop()

            socket
            |> assign(:moving, nil)
            |> assign(:velocity, 0)
          else
            socket
          end

        {:error, _} ->
          socket
      end

    Process.send_after(self(), :poll_sonar, @sonar_poll_interval)
    {:noreply, socket}
  end

  def handle_info(:physics_tick, socket) do
    keys = socket.assigns.keys_pressed
    velocity = socket.assigns.velocity
    prev_moving = socket.assigns.moving
    max_speed = socket.assigns.max_speed

    w = MapSet.member?(keys, "w")
    s = MapSet.member?(keys, "s")
    a = MapSet.member?(keys, "a")
    d = MapSet.member?(keys, "d")
    q = MapSet.member?(keys, "q")
    e = MapSet.member?(keys, "e")

    # Handle rotation separately (instant, no physics)
    socket =
      cond do
        q ->
          # Only send if not already rotating left
          if prev_moving != :rotate_left, do: Board.drive(:rotate_left, max_speed)
          assign(socket, :moving, :rotate_left)

        e ->
          # Only send if not already rotating right
          if prev_moving != :rotate_right, do: Board.drive(:rotate_right, max_speed)
          assign(socket, :moving, :rotate_right)

        true ->
          # Calculate new velocity based on input
          new_velocity =
            cond do
              # W accelerates forward, or brakes if going backward
              w and velocity < 0 -> velocity + @brake_decel
              w -> min(velocity + @acceleration, max_speed)
              # S accelerates backward, or brakes if going forward
              s and velocity > 0 -> velocity - @brake_decel
              s -> max(velocity - @acceleration, -max_speed)
              # No W/S - coast toward zero (friction)
              velocity > 0 -> max(velocity - @friction, 0)
              velocity < 0 -> min(velocity + @friction, 0)
              true -> 0
            end

          # Update steering
          new_steering =
            cond do
              a and not d -> -1
              d and not a -> 1
              true -> 0
            end

          # Check collision avoidance
          new_velocity =
            if new_velocity > 0 and too_close?(socket) do
              0
            else
              new_velocity
            end

          # Determine direction and send motor command
          {direction, abs_speed} = velocity_to_direction(new_velocity, new_steering)
          new_moving = if(abs_speed > 0, do: direction, else: nil)

          # Only send commands when state changes or when actively moving
          cond do
            # Just stopped - send stop once
            new_moving == nil and prev_moving != nil ->
              Board.stop()

            # Moving - send command (speed might be changing)
            new_moving != nil ->
              Board.drive(direction, abs_speed)

            # Already stopped - don't send anything
            true ->
              :ok
          end

          socket
          |> assign(:velocity, new_velocity)
          |> assign(:steering, new_steering)
          |> assign(:moving, new_moving)
      end

    Process.send_after(self(), :physics_tick, @physics_tick_ms)
    {:noreply, socket}
  end

  # Private helpers for keyboard controls

  defp update_drive_from_keys(socket) do
    # With physics, just update key state - physics_tick handles the rest
    socket
  end

  defp velocity_to_direction(velocity, steering) do
    abs_speed = abs(round(velocity))

    direction =
      cond do
        abs_speed == 0 -> :stop
        velocity > 0 and steering < 0 -> :forward_left
        velocity > 0 and steering > 0 -> :forward_right
        velocity > 0 -> :forward
        # Reverse steering is inverted (like a real car)
        velocity < 0 and steering < 0 -> :backward_right
        velocity < 0 and steering > 0 -> :backward_left
        velocity < 0 -> :backward
        true -> :stop
      end

    {direction, abs_speed}
  end

  defp too_close?(socket) do
    case socket.assigns.sonar_distance do
      nil -> false
      distance -> distance < @min_safe_distance_mm
    end
  end

  defp gimbal_step(direction, socket) do
    step = socket.assigns.gimbal_step
    pan = socket.assigns.pan
    tilt = socket.assigns.tilt

    # Servo directions:
    # - Tilt (servo 5): lower pulse = look up, higher pulse = look down
    # - Pan (servo 6): lower pulse = look right, higher pulse = look left
    {new_pan, new_tilt} =
      case direction do
        # decrease = look up
        :up -> {pan, max(tilt - step, socket.assigns.tilt_min)}
        # increase = look down
        :down -> {pan, min(tilt + step, socket.assigns.tilt_max)}
        # increase = look left
        :left -> {min(pan + step, socket.assigns.pan_max), tilt}
        # decrease = look right
        :right -> {max(pan - step, socket.assigns.pan_min), tilt}
      end

    if new_pan != pan, do: Board.set_servo(6, new_pan)
    if new_tilt != tilt, do: Board.set_servo(5, new_tilt)

    socket
    |> assign(:pan, new_pan)
    |> assign(:tilt, new_tilt)
  end

  defp set_led(:sonar1, %{r: r, g: g, b: b}), do: Board.Sonar.set_pixel(0, r, g, b)
  defp set_led(:sonar2, %{r: r, g: g, b: b}), do: Board.Sonar.set_pixel(1, r, g, b)
  defp set_led(:board1, %{r: r, g: g, b: b}), do: Board.set_rgb(1, r, g, b)
  defp set_led(:board2, %{r: r, g: g, b: b}), do: Board.set_rgb(2, r, g, b)

  defp voltage_to_percentage(mv) when mv >= 8400, do: 100
  defp voltage_to_percentage(mv) when mv <= 6000, do: 0
  defp voltage_to_percentage(mv), do: round((mv - 6000) / (8400 - 6000) * 100)

  defp format_distance(mm) when mm >= 1000, do: "#{Float.round(mm / 10, 0) |> trunc()} cm"
  defp format_distance(mm), do: "#{Float.round(mm / 10, 1)} cm"

  defp distance_hud_class(nil), do: "bg-black/50 text-white/50"
  defp distance_hud_class(mm) when mm < 150, do: "bg-red-500/80 text-white"
  defp distance_hud_class(mm) when mm < 300, do: "bg-yellow-500/80 text-black"
  defp distance_hud_class(_mm), do: "bg-green-500/60 text-white"
end
