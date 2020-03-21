defmodule SwitchX.Test.Connection do
  use ExUnit.Case, async: false

  alias SwitchX.{
    Connection
  }

  describe "Test authentication" do
    setup do
      port = 9900

      connection_opts = [
        host: "127.0.0.1",
        port: port
      ]

      SwitchX.Test.Mock.ESLServer.start_link(port)
      {:ok, client} = Connection.Inbound.start_link(connection_opts)

      {
        :ok,
        conn: client
      }
    end

    test "auth/2 Accepted", context do
      assert {:ok, "Accepted"} = SwitchX.auth(context.conn, "ClueCon")
    end

    test "auth/2 Denied", context do
      assert {:error, "Denied"} = SwitchX.auth(context.conn, "Incorrect")
    end

    test "try to query an api without be authed", context do
      assert {:error, _reason} = SwitchX.api(context.conn, "global getvar")
    end
  end

  describe "Test Inbound operations all authenticated" do
    setup do
      port = 9901

      connection_opts = [
        host: "127.0.0.1",
        port: port
      ]

      SwitchX.Test.Mock.ESLServer.start_link(port)
      {:ok, client} = Connection.Inbound.start_link(connection_opts)
      {:ok, "Accepted"} = SwitchX.auth(client, "ClueCon")

      {
        :ok,
        conn: client
      }
    end

    test "api/2 global_getvar", context do
      assert {:ok, _data} = SwitchX.api(context.conn, "global_getvar")
    end

    test "api/2 uuid_getvar", context do
      assert {:ok, _data} =
               SwitchX.api(
                 context.conn,
                 "uuid_getvar a1024ff5-a5b3-4c0a-abd3-fd4a89508b5b current_application"
               )
    end

    test "parse background_job event", context do
      assert :ok = SwitchX.listen_event(context.conn, "BACKGROUND_JOB")
      assert_receive {:switchx_event, _event}, 100
    end

    test "originate/3", context do
      assert {:ok, "7f4de4bc-17d7-11dd-b7a0-db4edd065621"} =
               SwitchX.originate(context.conn, "user/200", "&park()")
    end

    test "originate/3 no answer", context do
      assert {:error, "NO_ANSWER"} = SwitchX.originate(context.conn, "user/480", "&park()")
    end

    test "originate/4 using expand prefix", context do
      assert {:ok, "7f4de4bc-17d7-11dd-b7a0-db4edd065621"} =
               SwitchX.originate(context.conn, "${verto_contact(200)}", "&park()", :expand)
    end

    test "linger/1", context do
      assert {:ok, "Lingering"} = SwitchX.linger(context.conn)
    end

    test "send_event/3", context do
      event_headers =
        SwitchX.Event.Headers.new(%{
          "profile": "external",
          "content-type": "text/plain",
          "to-uri": "sip:1@2.3.4.5",
          "from-uri": "sip:1@1.2.3.4",
          "content-length": 15
        })

      event_body = "test"

      event = SwitchX.Event.new(event_headers, event_body)
      assert {:ok, _event} = SwitchX.send_event(context.conn, "SEND_INFO", event)
    end

    test "send_event/4 attach event uuid", context do
      event_headers =
        SwitchX.Event.Headers.new(%{
          "profile": "external",
          "content-type": "text/plain",
          "to-uri": "sip:1@2.3.4.5",
          "from-uri": "sip:1@1.2.3.4",
          "content-length": 15
        })

      event_body = "test"

      event = SwitchX.Event.new(event_headers, event_body)

      assert {:ok, _event} =
               SwitchX.send_event(
                 context.conn,
                 "SEND_INFO",
                 event,
                 "7f4de4bc-17d7-11dd-b7a0-db4edd065621"
               )
    end

    test "send_message/2 returns {:error, reason} when using in inbound mode", context do
      event_headers =
        SwitchX.Event.Headers.new(%{
          "call-command": "execute",
          "execute-app-name": "playback",
          "execute-app-arg": "/tmp/test.wav"
        })

      event = SwitchX.Event.new(event_headers)
      assert {:error, _reason} = SwitchX.send_message(context.conn, event)
    end

    test "send_message/3", context do
      event_headers =
        SwitchX.Event.Headers.new(%{
          "call-command": "hangup",
          "hangup-cause": "NORMAL_CLEARING",
        })

      event = SwitchX.Event.new(event_headers)

      assert {:ok,
              %SwitchX.Event{
                body: "",
                headers: %{
                  "Content-Type" => "command/reply",
                  "Reply-Text" => "+OK"
                }
              }} = SwitchX.send_message(context.conn, "UUID", event)
    end
  end
end
