defmodule Board.LEDs do
  @moduledoc """
  Tracks LED state for persistence across page refreshes.
  """

  use Agent

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        %{
          sonar1: %{r: 0, g: 0, b: 0},
          sonar2: %{r: 0, g: 0, b: 0},
          board1: %{r: 0, g: 0, b: 0},
          board2: %{r: 0, g: 0, b: 0}
        }
      end,
      name: __MODULE__
    )
  end

  def get_all do
    Agent.get(__MODULE__, & &1)
  end

  def get(led_id) do
    Agent.get(__MODULE__, &Map.get(&1, led_id))
  end

  def set(led_id, rgb) do
    Agent.update(__MODULE__, &Map.put(&1, led_id, rgb))
  end
end
