defmodule SwitchX.Test.Connection.Outbound.OutboundSession do
  def start_link(conn), do: {:ok, "pid"}
end

defmodule SwitchX.Test.Connection.Outbound do
  use ExUnit.Case, async: false

  alias SwitchX.{
    Connection
  }

  setup do
    {:ok, server} =
      Connection.Outbound.start_link(
        SwitchX.Test.Connection.Outbound.OutboundSession,
        host: "127.0.0.1",
        port: 9998
      )

    # Waiting for the server get ready
    Process.sleep(1)
    host = {127, 0, 0, 1}
    port = 9998
    {:ok, sock} = :gen_tcp.connect(host, port, [:binary, active: :once, packet: :raw])

    {
      :ok,
      server: server, sock: sock
    }
  end

  test "Receive connected", %{sock: sock} do
    assert_receive {:tcp, ^sock, "connect\n\n"}, 100
  end
end
