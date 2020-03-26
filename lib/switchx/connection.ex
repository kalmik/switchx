defmodule SwitchX.Connection do
  @moduledoc false

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
    commands_sent: :queue.new(),
    applications_pending: Map.new()
  ]

  def callback_mode() do
    :handle_event_function
  end

  def start_link(owner, socket, :inbound) when is_port(socket) and is_pid(owner) do
    :gen_statem.start_link(__MODULE__, [owner, socket, :inbound], [])
  end

  def start_link(session_module, socket, :outbound) do
    :gen_statem.start_link(__MODULE__, [session_module, socket, :outbound], [])
  end

  def init([owner, socket, :inbound]) when is_port(socket) do
    {:ok, {host, port}} = :inet.peername(socket)

    data = %__MODULE__{
      host: host,
      port: port,
      owner: owner,
      socket: socket,
      connection_mode: :inbound
    }

    :inet.setopts(socket, active: :once)

    {:ok, :connecting, data}
  end

  def init([session_module, socket, :outbound]) when is_port(socket) do
    {:ok, {host, port}} = :inet.peername(socket)
    {:ok, owner} = apply(session_module, :start_link, [self()])

    data = %__MODULE__{
      host: host,
      port: port,
      owner: owner,
      socket: socket,
      connection_mode: :outbound
    }

    :inet.setopts(socket, active: :once)

    # Subscribing all my events
    :gen_tcp.send(socket, "connect\n\nmyevents\n\n")

    {:ok, :ready, data}
  end

  ## Handler events ##

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
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(:call, {:sendevent, event_name, event, event_uuid}, from, data) do
    event =
      case event_uuid do
        nil -> event
        uuid -> put_in(event.headers["unique-id"], uuid)
      end

    :gen_tcp.send(data.socket, "sendevent #{event_name}\n#{SwitchX.Event.dump(event)}\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(
        :call,
        {:sendmsg, uuid, %{headers: %{"Event-UUID" => event_uuid}} = event},
        from,
        data
      ) do
    :gen_tcp.send(data.socket, "sendmsg #{uuid}\n#{SwitchX.Event.dump(event)}\n\n")
    data = put_in(data.applications_pending, Map.put(data.applications_pending, event_uuid, from))
    {:keep_state, data}
  end

  def ready(:call, {:sendmsg, uuid, event}, from, data) do
    :gen_tcp.send(data.socket, "sendmsg #{uuid}\n#{SwitchX.Event.dump(event)}\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(:call, {:sendmsg, _event}, from, %{connection_mode: :inbound} = data) do
    :gen_statem.reply(
      from,
      {:error, "UUID is required for inbound mode, see SwitchX.send_message/3."}
    )

    {:keep_state, data}
  end

  def ready(
        :call,
        {:sendmsg, %{headers: %{"Event-UUID" => event_uuid}} = event},
        from,
        %{connection_mode: :outbound} = data
      ) do
    :gen_tcp.send(data.socket, "sendmsg \n#{SwitchX.Event.dump(event)}\n\n")
    data = put_in(data.applications_pending, Map.put(data.applications_pending, event_uuid, from))
    {:keep_state, data}
  end

  def ready(:call, {:sendmsg, event}, from, %{connection_mode: :outbound} = data) do
    # When outbound socket we can sendmsg without specifying the channel UUID, it's implicit
    :gen_tcp.send(data.socket, "sendmsg \n#{SwitchX.Event.dump(event)}\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(:call, {:myevents, nil}, from, %{connection_mode: :inbound} = data) do
    :gen_statem.reply(
      from,
      {:error, "UUID is required for inbound mode, see SwitchX.my_events/2."}
    )

    {:keep_state, data}
  end

  def ready(:call, {:myevents, nil}, from, data) do
    :gen_tcp.send(data.socket, "myevents\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(:call, {:myevents, uuid}, from, data) do
    :gen_tcp.send(data.socket, "myevents #{uuid}\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(:call, {:exit}, from, data) do
    :gen_tcp.send(data.socket, "exit\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
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
    # Subscribing CHANNEL_EXECUTE_COMPLETE in order to handle correctly application responses
    :gen_tcp.send(data.socket, "event plain CHANNEL_EXECUTE_COMPLETE\n\n")
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

  def ready(
        :event,
        %{headers: %{"Content-Type" => "command/reply", "Reply-Text" => "+OK will linger"}},
        data
      ) do
    {:keep_state, reply_from_queue("commands_sent", {:ok, "Lingering"}, data)}
  end

  def ready(:event, %{headers: %{"Content-Type" => "api/response"}} = event, data) do
    {:keep_state, reply_from_queue("api_calls", {:ok, event}, data)}
  end

  def ready(:event, %{headers: %{"Content-Type" => "command/reply"}} = event, data) do
    {:keep_state, reply_from_queue("commands_sent", {:ok, event}, data)}
  end

  def ready(
        :event,
        %{headers: %{"Event-Name" => "CHANNEL_EXECUTE_COMPLETE", "Application-UUID" => app_uuid}} =
          event,
        data
      ) do
    reply_to = Map.get(data.applications_pending, app_uuid)

    unless is_nil(reply_to),
      do: :gen_statem.reply(reply_to, event)

    {:keep_state, data}
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
