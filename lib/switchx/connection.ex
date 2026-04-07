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
    :session_module,
    api_calls: :queue.new(),
    commands_sent: :queue.new(),
    applications_pending: Map.new()
  ]

  @impl true
  def callback_mode() do
    :handle_event_function
  end

  def start_link(owner, socket, :inbound) when is_port(socket) and is_pid(owner) do
    :gen_statem.start_link(__MODULE__, [owner, socket, :inbound], [])
  end

  def start_link(session_module, socket, :outbound) do
    :gen_statem.start_link(__MODULE__, [session_module, socket, :outbound], [])
  end

  @impl true
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
    post_init(data)
    {:ok, :connecting, data}
  end

  @impl true
  def init([session_module, socket, :outbound]) when is_port(socket) do
    {:ok, {host, port}} = :inet.peername(socket)

    data = %__MODULE__{
      host: host,
      port: port,
      owner: nil,
      socket: socket,
      connection_mode: :outbound,
      session_module: session_module
    }

    send(self(), :read_data)
    post_init(data)
    {:ok, :connecting, data}
  end

  defp post_init(data) do
    Logger.info("SwitchX #{inspect self()} Starting.")
    :telemetry.execute([:switchx, :connection, data.connection_mode], %{value: 1}, %{})
  end

  ## Handler events ##
  @impl true
  def handle_event({:call, from}, {:close}, _state, data) do
    :gen_tcp.close(data.socket)
    :gen_statem.reply(from, :ok)
    {:next_state, :disconnected, data}
  end

  @impl true
  def handle_event({:call, from}, message, state, data) do
    apply(__MODULE__, state, [:call, message, from, data])
  end

  @impl true
  def handle_event(:info, {:tcp, _socket, "\n"}, _state, data) do
    # Empty line discarding
    {:keep_state, data}
  end

  @impl true
  def handle_event(:info, :read_data, :connecting, data) do
    :gen_tcp.send(data.socket, "connect\n\n")
    event = Socket.recv(data.socket)

    {:ok, owner} = apply(data.session_module, :start_link, [self(), event])
    data = put_in(data.owner, owner)

    :inet.setopts(data.socket, active: :once)
    {:next_state, :ready, data}
  end

  @impl true
  def handle_event(:info, {:tcp, socket, payload}, state, data) do
    event = Socket.recv(socket, payload)
    :inet.setopts(socket, active: :once)

    content_type = event.headers["Content-Type"]
    # Parsing disconnect for any state
    case content_type do
      "text/disconnect-notice" -> handle_event(:disconnect, event, state, data)
      ^content_type -> apply(__MODULE__, state, [:event, event, data])
    end
  end

  @impl true
  def handle_event(:info, _message, _state, data) do
    {:keep_state, data}
  end

  @impl true
  def handle_event(:disconnect, event, state, data) do
    Logger.info("handle_event :disconnect #{inspect(event)}")
    case event.headers["Content-Disposition"] do
      "linger" ->
        Logger.info("Disconnect hold due to linger, keeping state #{inspect(state)}")
        {:keep_state, data}

      _disposition ->
        Logger.info("Disconnect received, closing socket.")
        :gen_tcp.close(data.socket)
        {:next_state, :disconnected, data}
    end
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
    :gen_statem.reply(from, {:ok, "Listening #{event_name}"})
    {:keep_state, data}
  end

  def ready(:call, {:linger}, from, data) do
    :gen_tcp.send(data.socket, "linger\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(:call, {:linger, linger_time}, from, data) do
    :gen_tcp.send(data.socket, "linger ${linger_time}\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(:call, {:sendevent, event_name, event, event_uuid}, from, data) do
    event =
      case event_uuid do
        nil -> event
        uuid -> put_in(event.headers["unique-id"], uuid)
      end

    event =
      put_in(
        event.headers,
        Map.merge(event.headers, %{
          "Event-Name" => event_name
        })
      )

    :gen_tcp.send(data.socket, "sendevent #{event_name}\n#{SwitchX.Event.dump(event)}\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def ready(:call, {:sendmsg, nil, _event}, from, %{connection_mode: :inbound} = data) do
    :gen_statem.reply(
      from,
      {:error, "UUID is required for inbound mode, see SwitchX.send_message/3."}
    )

    {:keep_state, data}
  end

  def ready(:call, {:sendmsg, uuid, event}, from, data) do
    case uuid do
      nil -> :gen_tcp.send(data.socket, "sendmsg\n#{SwitchX.Event.dump(event)}\n\n")
      uuid -> :gen_tcp.send(data.socket, "sendmsg #{uuid}\n#{SwitchX.Event.dump(event)}\n\n")
    end

    event_uuid = Map.get(event.headers, "Event-UUID")

    data =
      if is_nil(event_uuid) do
        put_in(data.commands_sent, :queue.in(from, data.commands_sent))
      else
        put_in(data.applications_pending, Map.put(data.applications_pending, event_uuid, from))
      end

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

  def ready(:call, {:bgapi, args}, from, data) do
    # job_uuid = UUID.uuid4()
    :gen_tcp.send(data.socket, "bgapi #{args}\n\n")
    data = put_in(data.commands_sent, :queue.in(from, data.commands_sent))
    {:keep_state, data}
  end

  def disconnected(:call, _payload, from, data) do
    :gen_statem.reply(from, {:error, :disconnected})
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
    Logger.info("ESL Authenticated to FreeSWITCH")
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
    # Logger.info("SwitchX ready: #{inspect(event)}")
    send(data.owner, {:switchx_event, event})
    {:keep_state, data}
  end

  def disconnected(:event, %{headers: %{"Content-Type" => "text/disconnect-notice"}} = event, data) do

    Logger.info("SwitchX disconnected with text/disconnect-notice: #{inspect(event)}")
    send(data.owner, {:switchx_event, event})
    {:keep_state, data}
  end

  def disconnected(:event, payload, data) do
    Logger.info("SwitchX disconnected: #{inspect(payload)}")
    {:keep_state, data}
  end


  @impl true
  def terminate(reason, _state, data) do
    :telemetry.execute([:switchx, :connection, data.connection_mode], %{value: -1}, %{})
    Logger.info("SwitchX #{inspect self()} Finishing. #{inspect reason}")
    :ok
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
