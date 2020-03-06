defmodule Examples.InboundSocket.Listen do
  @moduledoc false
  use GenServer

  def start_link(), do: GenServer.start_link(__MODULE__, [], [])
  def init([]) do
    {:ok, conn} = SwitchX.Connection.Inbound.start_link([host: "127.0.0.1", port: 8021])
    SwitchX.auth(conn, "ClueCon")
    SwitchX.listen_event(conn, "HEARTBEAT")

    state = %{
      conn: conn
    }

    {:ok, state}
  end

  def handle_info({:switchx_event, event, _socket}, state) do
    IO.inspect(event)
    {:noreply, state}
  end
end

