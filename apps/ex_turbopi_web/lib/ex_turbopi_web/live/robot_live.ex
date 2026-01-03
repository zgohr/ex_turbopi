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
  @sonar_poll_interval 200
  @min_safe_distance_mm 100

  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :poll_battery)
      send(self(), :poll_sonar)
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
      |> assign(:speed, 25)
      |> assign(:moving, nil)
      |> assign(:leds_expanded, false)
      |> assign(:battery_voltage, nil)
      |> assign(:battery_percentage, nil)
      |> assign(:camera_streaming, Board.camera_streaming?())
      |> assign(:camera_stream_url, Board.camera_stream_url())
      |> assign(:sonar_distance, nil)
      # Telemetry state
      |> assign(:voltage_history, telemetry.voltage_history)
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
            <form phx-change="set_speed" class="flex items-center gap-2">
              <span class="text-sm">Speed:</span>
              <input
                type="range"
                min="10"
                max="50"
                value={@speed}
                class="range range-xs w-24"
                name="speed"
              />
              <span class="text-sm w-8">{@speed}%</span>
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
          voltage_history={@voltage_history}
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

  attr :voltage_history, :list, default: []
  attr :current_voltage, :integer, default: nil
  attr :active, :map, default: %{camera: false, motors: false, motor_speed: 0}
  attr :draw, :map, default: %{camera: 0, motors: 0, total: 0}

  defp power_monitor(assigns) do
    ~H"""
    <div class="card bg-base-200 p-4">
      <h3 class="font-medium mb-3">Power Monitor</h3>

      <%!-- Active consumers with estimated draw --%>
      <div class="flex flex-wrap gap-4 text-sm mb-3">
        <div class={["flex items-center gap-1", @active.camera && "text-warning"]}>
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
            <span>Total: ~{@draw.total}mA</span>
          </div>
        <% end %>
      </div>

      <%!-- Voltage sparkline --%>
      <div class="h-16 bg-base-300 rounded relative overflow-hidden">
        <%= if length(@voltage_history) > 1 do %>
          <svg viewBox="0 0 100 40" preserveAspectRatio="none" class="w-full h-full">
            <polyline
              points={voltage_sparkline(@voltage_history)}
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              class={sparkline_color(@current_voltage)}
            />
          </svg>
        <% else %>
          <div class="absolute inset-0 flex items-center justify-center text-base-content/30 text-sm">
            Collecting data...
          </div>
        <% end %>
      </div>
      <div class="flex justify-between text-xs text-base-content/50 mt-1">
        <span>5m ago</span>
        <span>
          <%= if @current_voltage do %>
            {Float.round(@current_voltage / 1000, 2)}V
          <% else %>
            --
          <% end %>
        </span>
      </div>
    </div>
    """
  end

  defp voltage_sparkline(history) when length(history) < 2, do: ""

  defp voltage_sparkline(history) do
    # Get min/max for scaling
    voltages = Enum.map(history, fn {_ts, v} -> v end)
    min_v = Enum.min(voltages)
    max_v = Enum.max(voltages)

    # Add some padding to the range
    # At least 100mV range
    range = max(max_v - min_v, 100)
    min_v = min_v - 50
    max_v = min_v + range + 100

    # Reverse so oldest is first (left side of graph)
    history = Enum.reverse(history)
    count = length(history)

    history
    |> Enum.with_index()
    |> Enum.map(fn {{_ts, voltage}, idx} ->
      x = idx / max(count - 1, 1) * 100
      y = 40 - (voltage - min_v) / (max_v - min_v) * 40
      "#{Float.round(x, 1)},#{Float.round(y, 1)}"
    end)
    |> Enum.join(" ")
  end

  defp sparkline_color(nil), do: "text-base-content/50"
  defp sparkline_color(mv) when mv >= 7400, do: "text-success"
  defp sparkline_color(mv) when mv >= 6800, do: "text-warning"
  defp sparkline_color(_mv), do: "text-error"

  # Keyboard controls
  def handle_event("keydown", %{"key" => key}, socket) do
    socket = handle_key_press(key, socket)
    {:noreply, socket}
  end

  def handle_event("keyup", %{"key" => key}, socket) do
    socket = handle_key_release(key, socket)
    {:noreply, socket}
  end

  # Touch/click controls
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
      |> assign(:voltage_history, telemetry.voltage_history)
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
          if socket.assigns.moving == :forward and distance < @min_safe_distance_mm do
            Board.stop()
            assign(socket, :moving, nil)
          else
            socket
          end

        {:error, _} ->
          socket
      end

    Process.send_after(self(), :poll_sonar, @sonar_poll_interval)
    {:noreply, socket}
  end

  # Private helpers for keyboard controls

  defp handle_key_press(key, socket) do
    case String.downcase(key) do
      "w" ->
        drive_and_assign(:forward, socket)

      "s" ->
        drive_and_assign(:backward, socket)

      "a" ->
        drive_and_assign(:left, socket)

      "d" ->
        drive_and_assign(:right, socket)

      "q" ->
        drive_and_assign(:rotate_left, socket)

      "e" ->
        drive_and_assign(:rotate_right, socket)

      "arrowup" ->
        gimbal_step(:up, socket)

      "arrowdown" ->
        gimbal_step(:down, socket)

      "arrowleft" ->
        gimbal_step(:left, socket)

      "arrowright" ->
        gimbal_step(:right, socket)

      # Space bar - stop
      " " ->
        Board.stop()
        assign(socket, :moving, nil)

      _ ->
        socket
    end
  end

  defp handle_key_release(key, socket) do
    case String.downcase(key) do
      k when k in ["w", "s", "a", "d", "q", "e"] ->
        Board.stop()
        assign(socket, :moving, nil)

      _ ->
        socket
    end
  end

  defp drive_and_assign(direction, socket) do
    if too_close_to_drive_forward?(direction, socket) do
      Board.stop()
      assign(socket, :moving, nil)
    else
      Board.drive(direction, socket.assigns.speed)
      assign(socket, :moving, direction)
    end
  end

  defp too_close_to_drive_forward?(:forward, socket) do
    case socket.assigns.sonar_distance do
      nil -> false
      distance -> distance < @min_safe_distance_mm
    end
  end

  defp too_close_to_drive_forward?(_, _socket), do: false

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
