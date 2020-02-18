defmodule SwitchX.Connection do
  @behaviour :gen_statem
  require Logger

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

    case data.connection_mode do
      :inbound -> {:ok, :connecting, data}
      :outbouncd -> {:ok, :ready, data}
      _ -> {:ok, :disconnected, data}
    end
  end

  defp consume(payload, socket) when is_binary(payload) do
      case :gen_tcp.recv(socket, 0) do
        {:ok, "\n"} -> consume(SwitchX.Event.new(payload), socket)
        {:ok, data} -> consume(payload <> data, socket)
      end
  end

  defp consume(event, socket) do
    content_length = String.to_integer(Map.get(event.headers, "Content-Length", "0"))

    if content_length > 0 do
      :inet.setopts(socket, packet: :raw)

      packet =
        case :gen_tcp.recv(socket, content_length, 1_000) do
          {:error, :timeout} -> ""
          {:ok, packet} -> packet
        end

      :inet.setopts(socket, packet: :line)
      new_event = consume(SwitchX.Event.new(packet), socket)
      SwitchX.Event.merge(event, new_event)
    else
      event
    end
  end

  def handle_event({:call, from}, message, state, data) do
    apply(__MODULE__, state, [:call, message, from, data])
  end

  def handle_event(:info, {:tcp, _socket, "\n"}, _state, data) do
    # Empty line discarding
    {:keep_state, data}
  end

  def handle_event(:info, {:tcp, socket, payload}, state, data) do
    event = consume(payload, socket)
    :inet.setopts(socket, active: :once)
    apply(__MODULE__, state, [:event, event, data])
  end

  def handle_event(:info, _message, _state, data) do
    {:keep_state, data}
  end

  ## API ##

  def auth(conn, password), do: :gen_statem.call(conn, {:auth, password})
  def api(conn, args), do: :gen_statem.call(conn, {:api, args})
  def listen_event(conn, event_name), do: :gen_statem.call(conn, {:listen_event, event_name})

  ## CALL STATE FUNCTIONS ##
  def connecting(:call, {:auth, password}, from, data) do
    data = put_in(data.password, password)
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def authenticating(:call, {:auth, password}, from, data) do
    data = put_in(data.password, password)
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))

    :gen_tcp.send(data.socket, "auth #{data.password}\n\n")
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

    data =
      case :queue.out(data.commands_sent) do
        {{_, reply_to}, q} ->
          :gen_statem.reply(reply_to, {:ok, "Accepted"})
          put_in(data.api_calls, q)

        {:empty, _} ->
          data
      end

    {:next_state, :ready, data}
  end

  def authenticating(
        :event,
        %{headers: %{"Content-Type" => "command/reply", "Reply-Text" => "-ERR invalid"}},
        data
      ) do
    Logger.info("Fail to Connect")

    data =
      case :queue.out(data.commands_sent) do
        {{_, reply_to}, q} ->
          :gen_statem.reply(reply_to, {:error, "Denied"})
          put_in(data.api_calls, q)

        {:empty, _} ->
          data
      end

    {:next_state, :disconnected, data}
  end

  def disconnected(:event, %{headers: %{"Content-Type" => "text/disconnect-notice"}}, data) do
    {:keep_state, data}
  end

  def ready(:event, %{headers: %{"Content-Type" => "api/response"}} = event, data) do
    data =
      case :queue.out(data.api_calls) do
        {{_, reply_to}, q} ->
          :gen_statem.reply(reply_to, {:ok, event})
          put_in(data.api_calls, q)

        {:empty, _} ->
          data
      end

    {:keep_state, data}
  end

  def ready(:event, event, data) do
    send(data.owner, {:event, event, data.socket})
    {:keep_state, data}
  end
end
