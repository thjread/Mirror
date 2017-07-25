defmodule Mirror.Network do
  use GenServer
  require Logger

  def test() do
    Mirror.Network.connect(Mirror.Network, 'localhost', 4001)
    Mirror.Network.send_message(Mirror.Network, "hello\r\n")
  end

  ## Public API

  @doc """
  Start a new server with `name`.
  """
  def start_link(name) do
    GenServer.start_link(__MODULE__, {:port, String.to_integer(System.get_env("PORT"))}, name: name)
  end

  @doc """
  Connect `server` to remote `host`, `port`.
  """
  def connect(server, host, port) do
    with {:socket, _} <- GenServer.call(server, {:connect, host, port}),
    do: :ok
  end

  @doc """
  Send `message` via `server`. Returns `:ok` or `{:error, :reason}`
  """
  def send_message(server, message) do
    GenServer.call(server, {:send, message})
  end

  @doc """
  Stop `server`.
  """
  def stop(server) do
    GenServer.stop(server)
  end

  ## Internal methods

  defp tcp_listen(port, listener) do
    server = self()
    task = Task.async(fn ->
      {:ok, socket} = :gen_tcp.accept(listener)
      Logger.info("Connected on port #{port} (server)")
      :gen_tcp.controlling_process(socket, server)
      GenServer.cast(server, {:connected, socket}) end)
    {:ok, task}
  end

  ## Server Callbacks

  def init({:port, port}) do
    {:ok, listener} = :gen_tcp.listen(port, [:binary, packet: :line, active: true, reuseaddr: true, keepalive: true])
    Logger.info("Accepting connections on port #{port}")
    {:ok, task} = tcp_listen(port, listener)
    {:ok, {{:listening, task}, %{port: port, listener: listener}}}
  end

  def handle_call({:send, message}, _from, {{:connected, socket}, state}) do
    :ok = :gen_tcp.send(socket, message)
    {:reply, :ok, {{:connected, socket}, state}}
  end
  def handle_call({:send, _message}, _from, state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:connect, host, port}, _from, {condition, state}) do
    response = :gen_tcp.connect(host, port, [:binary, packet: :line, active: true, reuseaddr: true, keepalive: true])
    case response do
      {:ok, socket} ->
        case condition do
          {:listening, task} -> Task.shutdown(task, :brutal_kill)
          {:connected, socket} -> :gen_tcp.close(socket)
          _ -> :nothing
        end
        Logger.info("Connected on port #{port} (client)")
        {:reply, {:socket, socket}, {{:connected, socket}, state}}
      {:error, reason} ->
        {:reply, {:error, reason}, {condition, state}}
    end
  end

  def handle_cast({:connected, socket}, {_condition, state}) do
    {:noreply, {{:connected, socket}, state}}
  end

  def handle_info({:tcp, _port, message}, state) do
    Logger.info("Message received: " <> message)
    Mirror.receive_message(Mirror, message)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _port}, {_condition, %{:port => port, :listener => listener} = state}) do
    Logger.info("Connection closed")
    {:ok, task} = tcp_listen(port, listener)
    {:noreply, {{:listening, task}, state}}
  end

  def handle_info(info, state) do
    Logger.debug("Mirror.Network.handle_info: " <> inspect(info, pretty: true))
    Logger.debug("State: " <> inspect(state, pretty: true))
    {:noreply, state}
  end
end
