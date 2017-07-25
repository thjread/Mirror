defmodule Mirror do
  use GenServer
  require Logger

  def test() do
    :ok = Mirror.Network.connect(Mirror.Network, 'localhost', 4001)
    message = %{"body" => "hello\n", "number" => 1, "version" => 1, "final" => true}
    Mirror.send_message(Mirror, message)

    callback = fn (message) -> IO.puts("Model callback: " <> inspect(message, pretty: true)) end
    :ok = Mirror.register_callback(Mirror, Mirror, callback)
  end

  ## Public API

  @doc """
  Start a new server with `name`.
  """
  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc """
  Send `message` via `server`. Returns `:ok` or `{:error, reason}`
  """
  def send_message(server, message) do
    GenServer.call(server, {:send, message})
  end

  @doc """
  Store new `message` in `server`.
  """
  def receive_message(server, message) do
    :ok = GenServer.call(server, {:receive, message})
  end

  @doc """
  Register a `callback` to be called when `server` receives a message. (`callback.(server, message)`)
  """
  def register_callback(server, ref, callback) do
    :ok = GenServer.call(server, {:register_callback, ref, callback})
    :ok
  end

  @doc """
  Remove callback associated with `ref` from `server`.
  """
  def remove_callback(server, ref) do
    :ok = GenServer.call(server, {:remove_callback, ref})
  end

  @doc """
  Stop `server`.
  """
  def stop(server) do
    GenServer.stop(server)
  end

  ## Server Callbacks

  def init(:ok) do
    Logger.info("Initialising new message model")
    received_table = :ets.new(:received_messages, [:set, :private])
    my_table = :ets.new(:my_messages, [:set, :private])
    {:ok, %{callbacks: %{}, received_table: received_table, my_table: my_table}}
  end

  def handle_call({:send, message}, _from, state) do
    {:ok, state} = store(message, true, state)
    res = Mirror.Network.send_message(Mirror.Network, Poison.encode!(message)<>"\n")
    case res do
      :ok -> {:reply, :ok, state}
      {:error, _}=err -> {:reply, err, state}
    end
  end

  def handle_call({:receive, message}, _from, %{:callbacks => cs} = state) do
    Logger.info("Model received message: " <> message)
    message = Poison.decode!(message)
    {:ok, state} = store(message, false, state)
    cs
    |> Enum.map(fn {_ref, callback} -> Task.async(fn () -> callback.(message) end) end)
    |> Enum.map(&Task.await(&1))
    {:reply, :ok, state}
  end

  def handle_call({:register_callback, ref, callback}, _from,
    %{:callbacks => cs} = state) do
    cs = Map.put(cs, ref, callback)
    {:reply, :ok, %{state | :callbacks => cs}}
  end

  def handle_call({:remove_callback, ref}, _from, %{:callbacks => cs} = state) do
    cs = Map.delete(cs, ref)
    {:reply, :ok, %{state | :callbacks => cs}}
  end

  def handle_info(info, state) do
    Logger.debug("Mirror.Network.handle_info: " <> inspect(info, pretty: true))
    {:noreply, state}
  end

  ## Internal methods

  defp store(message, mine, state) do
    Logger.info("Storing message: " <> inspect(message, pretty: true))
    message = Map.put(message, "requested", false)
    number = message["number"]
    version = message["version"]
    t =
      if mine do
        state[:my_table]
      else
        state[:received_table]
      end
    prev = :ets.lookup(t, number)
    case prev do
      [] -> request_to(number, mine, state)
      [%{final: true}] -> :dont_replace
      [%{final: false, version: v}] when v >= version -> :dont_replace
      _ -> :ets.insert(t, {number, message})
    end
    {:ok, state}
  end

  defp request_to(_number, _mine, _state) do
    :nothing
  end

  defp uuid() do
    :rand.uniform(4294967296)
  end
end
