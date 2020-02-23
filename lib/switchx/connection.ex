defmodule SwitchX.Connection do
  @behaviour :gen_statem
  require Logger

  alias SwitchX.Connection.{
    Socket
  }

  defstruct [
    :host,
    :port,
    :password,
    :owner,
    :socket,
    :connection_mode,
    :api_response_buffer,
    api_calls: :queue.new(),
    commands_sent: :queue.new()
  ]

  def callback_mode() do
    :handle_event_function
  end

  def start_link(owner, socket, connection_mode, password \\ nil) when is_port(socket) do
    :gen_statem.start_link(__MODULE__, [owner, socket, connection_mode, password], [])
  end

  def init([owner, socket, connection_mode, password]) when is_port(socket) do
    {:ok, {host, port}} = :inet.peername(socket)

    data = %__MODULE__{
      host: host,
      port: port,
      password: password,
      owner: owner,
      socket: socket,
      connection_mode: connection_mode
    }

    :inet.setopts(socket, active: :once)

    case data.connection_mode do
      :inbound ->
        {:ok, :connecting, data}

      :outbound ->
        :gen_tcp.send(socket, "connect\n\n")
        {:ok, :ready, data}

      _ ->
        :error
    end
  end

  ## API ##

  def change_owner(conn, owner), do: :gen_statem.call(conn, {:chown, owner})

  ## Handler events ##

  def handle_event({:call, from}, {:chown, owner}, _state, data) do
    data = put_in(data.owner, owner)
    :gen_statem.reply(from, :ok)
    {:keep_state, data}
  end

  def handle_event({:call, from}, message, state, data) do
    apply(__MODULE__, state, [:call, message, from, data])
  end

  def handle_event(:info, {:tcp, _socket, "\n"}, _state, data) do
    # Empty line discarding
    {:keep_state, data}
  end

  def handle_event(:info, {:tcp, socket, payload}, state, data) do
    event = Socket.recv(socket, payload)
    :inet.setopts(socket, active: :once)
    apply(__MODULE__, state, [:event, event, data])
  end

  def handle_event(:info, _message, _state, data) do
    {:keep_state, data}
  end

  ## CALL STATE FUNCTIONS ##
  def connecting(:call, {:auth, password}, from, data) do
    data = put_in(data.password, password)
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def connecting(:call, any_kind, from, data) do
    :gen_statem.reply(from, {:error, "Could not perform #{inspect(any_kind)}, not ready"})
    {:keep_state, data}
  end

  def authenticating(:call, {:auth, password}, from, data) do
    data = put_in(data.password, password)
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))

    :gen_tcp.send(data.socket, "auth #{data.password}\n\n")
    {:keep_state, data}
  end

  def authenticating(:call, any_kind, from, data) do
    :gen_statem.reply(from, {:error, "Could not perform #{inspect(any_kind)}, not ready"})
    {:keep_state, data}
  end

  def ready(:call, {:api, args}, from, data) do
    data = put_in(data.api_calls, :queue.in(from, data.api_calls))
    :gen_tcp.send(data.socket, "api #{args}\n\n")
    {:keep_state, data}
  end

  def ready(:call, {:listen_event, event_name}, from, data) do
    :gen_tcp.send(data.socket, "event plain #{event_name}\n\n")
    :gen_statem.reply(from, :ok)
    {:keep_state, data}
  end

  def ready(:call, {:linger}, from, data) do
    :gen_tcp.send(data.socket, "linger\n\n")
    :gen_statem.reply(from, :ok)
    {:keep_state, data}
  end

  ## Event STATE FUNCTIONS ##

  def connecting(
        :event,
        %{headers: %{"Content-Type" => "auth/request"}},
        %{password: password} = data
      )
      when is_binary(password) do
    :gen_tcp.send(data.socket, "auth #{data.password}\n\n")
    {:next_state, :authenticating, data}
  end

  def connecting(:event, %{headers: %{"Content-Type" => "auth/request"}}, data) do
    {:next_state, :authenticating, data}
  end

  def authenticating(
        :event,
        %{headers: %{"Content-Type" => "command/reply", "Reply-Text" => "+OK accepted"}},
        data
      ) do
    Logger.info("Connected")
    {:next_state, :ready, reply_from_queue("commands_sent", {:ok, "Accepted"}, data)}
  end

  def authenticating(
        :event,
        %{headers: %{"Content-Type" => "command/reply", "Reply-Text" => "-ERR invalid"}},
        data
      ) do
    Logger.info("Fail to Connect")
    {:next_state, :disconnected, reply_from_queue("commands_sent", {:error, "Denied"}, data)}
  end

  def disconnected(:event, %{headers: %{"Content-Type" => "text/disconnect-notice"}}, data) do
    {:keep_state, data}
  end

  def ready(:event, %{headers: %{"Content-Type" => "api/response"}} = event, data) do
    {:keep_state, reply_from_queue("api_calls", {:ok, event}, data)}
  end

  def ready(:event, event, data) do
    send(data.owner, {:switchx_event, event})
    {:keep_state, data}
  end

  ## HELPERS ##

  defp reply_from_queue(queue_name, response, data) do
    queue = Map.get(data, String.to_atom(queue_name))

    case :queue.out(queue) do
      {{_, reply_to}, q} ->
        :gen_statem.reply(reply_to, response)
        Map.put(data, String.to_atom(queue_name), q)

      {:empty, _} ->
        data
    end
  end
end
