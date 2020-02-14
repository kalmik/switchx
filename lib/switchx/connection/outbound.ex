defmodule SwitchX.Connection.Outbound do
  use GenServer

  @socket_opts [:binary, active: true, reuseaddr: true]

  defstruct [
    :bind_address,
    :bind_port,
    :con,
    clients: Map.new()
  ]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, [])

  def init(opts) do
    bind_address = Keyword.fetch!(opts, :bind_address)
    bind_port = Keyword.fetch!(opts, :bind_port)

    state = %__MODULE__{
      bind_address: bind_address,
      bind_port: bind_port
    }

    GenServer.cast(self(), {:start})
    {:ok, state}
  end

  def handle_cast({:start}, state) do
    # ++ [ip: state.bind_address]
    opts = @socket_opts
    {:ok, listen_socket} = :gen_tcp.listen(state.bind_port, opts)
    {:ok, socket} = :gen_tcp.accept(listen_socket)
    state = put_in(state.con, socket)
    {:noreply, state}
  end

  def handle_info({:tcp, socket, _payload}, state) do
    {:ok, pid} = SwitchX.Connection.start_link(self(), socket, :outbound)
    :gen_tcp.controlling_process(socket, pid)
    state = put_in(state.clients, Map.put(state.clients, socket, pid))
    {:noreply, state}
  end
end
