defmodule SwitchX.Test.Connection do
  use ExUnit.Case, async: false

  alias SwitchX.{
    Connection
  }

  defp assert_not_called(module, func) do
    call_history = :meck.history(module)

    assert Enum.filter(call_history, fn
             {_pid, {^module, ^func, _args}, _res} -> true
             _ -> false
           end)
           |> Enum.count() == 0,
           "#{module} #{func} is not expected to be called.\nCall History\n#{
             inspect(call_history)
           }"
  end

  describe "Handling call" do
    test "calling close" do
      :meck.new(:gen_tcp, [:unstick, :passthrough])
      :meck.expect(:gen_tcp, :close, fn _sock -> :ok end)

      from = {self(), make_ref()}
      initial_state = %Connection{}

      {action, state, _data} =
        Connection.handle_event({:call, from}, {:close}, :any, initial_state)

      assert :meck.called(:gen_tcp, :close, :_)
      assert action == :next_state
      assert state == :disconnected

      :meck.unload(:gen_tcp)
    end
  end

  describe "Handling disconnect incoming event" do
    setup do
      port = 9900

      connection_opts = [
        host: "127.0.0.1",
        port: port
      ]

      {:ok, server} = SwitchX.Test.Mock.ESLServer.start_link(port)
      Process.sleep(1_000)
      {:ok, client} = Connection.Inbound.start_link(connection_opts)
      SwitchX.auth(client, "ClueCon")

      {
        :ok,
        server: server, client: client
      }
    end

    test "incoming disconnect linger", context do
      :meck.new(:gen_tcp, [:unstick, :passthrough])
      :meck.expect(:gen_tcp, :close, fn _sock -> :ok end)
      {initial_state, _} = :sys.get_state(context.client)
      GenServer.cast(context.server, :send_disconnect_linger)
      Process.sleep(100)

      {current_state, _} = :sys.get_state(context.client)

      assert not :meck.called(:gen_tcp, :close, :_)
      assert current_state == initial_state

      :meck.unload(:gen_tcp)
    end

    test "incoming disconnect with no linger", context do
      :meck.new(:gen_tcp, [:unstick, :passthrough])
      :meck.expect(:gen_tcp, :close, fn _sock -> :ok end)
      GenServer.cast(context.server, :send_disconnect)
      Process.sleep(100)

      {current_state, _} = :sys.get_state(context.client)
      assert :meck.called(:gen_tcp, :close, :_)
      assert current_state == :disconnected

      :meck.unload(:gen_tcp)
    end
  end
end
