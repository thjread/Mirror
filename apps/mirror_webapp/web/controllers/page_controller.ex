defmodule MirrorWebapp.PageController do
  use MirrorWebapp.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
