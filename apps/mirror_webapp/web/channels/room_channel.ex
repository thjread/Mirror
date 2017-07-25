defmodule MirrorWebapp.RoomChannel do
  use Phoenix.Channel

  def join("room:lobby", _message, socket) do
    me = self()
    Mirror.register_callback(Mirror, MirrorWebapp.RoomChannel,
      fn (msg) -> receive_message(msg, me) end)
    {:ok, socket}
  end

  def join("room:" <> _other, _, _) do
    {:error, %{reason: "room does not exist"}}
  end

  def handle_in("message", msg, socket) do
    Mirror.send_message(Mirror, msg)
    {:noreply, socket}
  end

  def handle_info({:receive_message, message}, socket) do
    broadcast! socket, "message", message
    {:noreply, socket}
  end

  defp receive_message(message, me) do
    send(me, {:receive_message, message})
  end
end
