defmodule Board.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers before starting supervised processes
    attach_telemetry_handlers()

    children = [
      Board.Connection,
      Board.Sonar,
      Board.LineFollower,
      Board.Battery,
      Board.Camera,
      Board.Telemetry,
      Board.LEDs
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Board.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp attach_telemetry_handlers do
    :telemetry.attach_many(
      "board-telemetry-handler",
      [
        [:board, :battery, :reading],
        [:board, :camera, :state],
        [:board, :motors, :command]
      ],
      &Board.Telemetry.handle_event/4,
      nil
    )
  end
end
