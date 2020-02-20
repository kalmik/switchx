defmodule Examples.InboundSocket do
  def originate() do
    {:ok, conn} = SwitchX.Connection.Inbound.start_link([host: "127.0.0.1", port: 8021])
    SwitchX.auth(conn, "ClueCon")

    case SwitchX.originate(conn, "user/100", "&park()", :expand) do
      {:ok, uuid} -> "Success #{uuid}"
      {:error, term} -> "Error #{term}"
    end
  end
end

