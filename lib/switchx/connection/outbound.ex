defmodule SwitchX.Connection.Outbound do
  use Task, restart: :transient

  require Logger

  @socket_opts [:binary, active: false, reuseaddr: true]

  defstruct [
    :bind_address,
    :bind_port,
    :listen_socket,
    :mod
  ]

  def start_link(module, opts), do: Task.start_link(__MODULE__, :init, [module, opts])

  def init(module, opts) do
    mod = module
    bind_address = Keyword.fetch!(opts, :host)
    bind_port = Keyword.fetch!(opts, :port)

    {:ok, listen_socket} = :gen_tcp.listen(bind_port, @socket_opts)

    state = %__MODULE__{
      bind_address: bind_address,
      bind_port: bind_port,
      listen_socket: listen_socket,
      mod: mod
    }

    run(state)
  end

  def run(state) do
    socket =
      case :gen_tcp.accept(state.listen_socket) do
        {:ok, socket} ->
          Logger.info("New connection from #{inspect(:inet.peername(socket))}")
          {:ok, connection} = SwitchX.Connection.start_link(state.mod, socket, :outbound)
          :gen_tcp.controlling_process(socket, connection)
          run(state)

        _ ->
          :error
      end
  end
end
