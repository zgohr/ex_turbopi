defmodule ExTurbopiWeb.PageController do
  use ExTurbopiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
