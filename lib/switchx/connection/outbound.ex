defmodule SwitchX.Connection.Outbound do
  @moduledoc """
  Outbound mode means you make a daemon, and then have FreeSWITCH connect to it.
  You add an extension to the dialplan, and put <action application="socket" data="ip:port sync full"/> 

  In outbound mode, also known as the "socket application" (or socket client), FreeSWITCH makes outbound connections to another process
  (similar to Asterisk's FAGI model). Using outbound connections you can have FreeSWITCH call your own application(s) when particular events occur.

  See Event Socket Outbound for more details regarding things specific to outbound mode.
  """
  use Task, restart: :transient

  require Logger

  @socket_opts [:binary, active: false, reuseaddr: true]

  defstruct [
    :bind_address,
    :bind_port,
    :listen_socket,
    :mod
  ]

  @doc """
  Starts a new outbound server.

  Returns `{:ok, Pid}`

  ## Examples

      iex> parameters [
        host: "127.0.0.1",
        port: 9998,
      ]
      iex> SwitchX.Connection.Outbound.start_link(Examples.OutboundSession, parameters)
      {:ok, server_pid}

  """
  @spec start_link(module :: Module, opts :: Keyword) :: {:ok, server_pid :: Pid} | {:error, term}
  def start_link(module, opts), do: Task.start_link(__MODULE__, :init, [module, opts])

  @doc false
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

  @doc false
  def run(state) do
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
