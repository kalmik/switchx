defmodule SwitchX.Test.Mock.ESLServer do
  use GenServer

  @socket_opts [:binary, active: true, reuseaddr: true]

  defstruct [
    :bind_address,
    :bind_port,
    :socket
  ]

  def start_link(port), do: GenServer.start_link(__MODULE__, [port], [])

  def init([port]) do
    state = %__MODULE__{
      bind_address: "127.0.0.1",
      bind_port: port
    }

    GenServer.cast(self(), {:start})
    {:ok, state}
  end

  def close(conn), do: GenServer.call(conn, :close)

  def handle_call(:close, _from, state) do
    :gen_tcp.close(state.socket)
    Process.exit(self(), :normal)
    {:reply, :ok, state}
  end

  def handle_cast({:start}, state) do
    {:ok, listen_socket} = :gen_tcp.listen(state.bind_port, @socket_opts)
    {:ok, socket} = :gen_tcp.accept(listen_socket)
    state = put_in(state.socket, socket)
    :gen_tcp.send(socket, "Content-Type: auth/request\n\n")
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "auth ClueCon\n\n"}, state) do
    :gen_tcp.send(socket, "Content-Type: command/reply\nReply-Text: +OK accepted\n\n")
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "linger\n\n"}, state) do
    :gen_tcp.send(socket, "Content-Type: command/reply\nReply-Text: +OK will linger\n\n")
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "auth Incorrect\n\n"}, state) do
    :gen_tcp.send(socket, "Content-Type: command/reply\nReply-Text: -ERR invalid\n\n")
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "api global_getvar\n\n"}, state) do
    :gen_tcp.send(
      socket,
      "Content-Type: api/response\nContent-Length: 21\n\nhostname=edev-kalmik\n\n"
    )

    {:noreply, state}
  end

  def handle_info(
        {:tcp, socket,
         "api uuid_getvar a1024ff5-a5b3-4c0a-abd3-fd4a89508b5b current_application\n\n"},
        state
      ) do
    :gen_tcp.send(socket, "Content-Type: api/response\nContent-Length: 4\n\n")
    :gen_tcp.send(socket, "park")
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "event plain BACKGROUND_JOB\n\n"}, state) do
    message = """
    Content-Type: text/event-plain
    Content-Length: 582

    Job-UUID: 7f4db78a-17d7-11dd-b7a0-db4edd065621
    Job-Command: originate
    Job-Command-Arg: sofia/default/1005%20'%26park'
    Event-Name: BACKGROUND_JOB
    Core-UUID: 42bdf272-16e6-11dd-b7a0-db4edd065621
    FreeSWITCH-Hostname: ser
    FreeSWITCH-IPv4: 192.168.1.104
    FreeSWITCH-IPv6: 127.0.0.1
    Event-Date-Local: 2008-05-02%2007%3A37%3A03
    Event-Date-GMT: Thu,%2001%20May%202008%2023%3A37%3A03%20GMT
    Event-Date-timestamp: 1209685023894968
    Event-Calling-File: mod_event_socket.c
    Event-Calling-Function: api_exec
    Event-Calling-Line-Number: 609
    Content-Length: 40

    +OK 7f4de4bc-17d7-11dd-b7a0-db4edd065621\n\n
    """

    :gen_tcp.send(socket, message)
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "api originate user/200 &park()\n\n"}, state) do
    :gen_tcp.send(socket, "Content-Type: api/response\nContent-Length: 40\n\n")
    :gen_tcp.send(socket, "+OK 7f4de4bc-17d7-11dd-b7a0-db4edd065621\n\n")
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "api originate user/480 &park()\n\n"}, state) do
    :gen_tcp.send(socket, "Content-Type: api/response\nContent-Length: 14\n\n")
    :gen_tcp.send(socket, "-ERR NO_ANSWER\n\n")
    {:noreply, state}
  end

  def handle_info({:tcp, socket, "api expand originate ${verto_contact(200)} &park()\n\n"}, state) do
    :gen_tcp.send(socket, "Content-Type: api/response\nContent-Length: 40\n\n")
    :gen_tcp.send(socket, "+OK 7f4de4bc-17d7-11dd-b7a0-db4edd065621\n\n")
    {:noreply, state}
  end

  def handle_info(
        {:tcp, socket,
         "sendevent SEND_INFO\ncontent-length: 15\ncontent-type: text/plain\nfrom-uri: sip:1@1.2.3.4\nprofile: external\nto-uri: sip:1@2.3.4.5\n\ntest\n\n"},
        state
      ) do
    :gen_tcp.send(
      socket,
      "Content-Type: command/reply\nReply-Text: +OK 42b44d0f-e579-47f5-bbeb-e74b1940f169\n\n"
    )

    {:noreply, state}
  end

  def handle_info(
        {:tcp, socket,
         "sendevent SEND_INFO\ncontent-length: 15\ncontent-type: text/plain\nfrom-uri: sip:1@1.2.3.4\nprofile: external\nto-uri: sip:1@2.3.4.5\nunique-id: 7f4de4bc-17d7-11dd-b7a0-db4edd065621\n\ntest\n\n"},
        state
      ) do
    :gen_tcp.send(
      socket,
      "Content-Type: command/reply\nReply-Text: +OK 7f4de4bc-17d7-11dd-b7a0-db4edd065621\n\n"
    )

    {:noreply, state}
  end
end
