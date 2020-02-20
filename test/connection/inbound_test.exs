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
      assert_receive {:event, _event, _socket}, 100
    end
  end
end
