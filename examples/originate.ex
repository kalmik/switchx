defmodule Examples.InboundSocket do
  @moduledoc false
  def originate() do
    {:ok, conn} = SwitchX.Connection.Inbound.start_link([host: "192.168.56.10", port: 8021])
    SwitchX.auth(conn, "ClueCon")

    case SwitchX.originate(conn, "${verto_contact(800}", "&park()", :expand) do
      {:ok, uuid} ->
        IO.puts("Success #{uuid}")

        Process.sleep(1000)

        IO.puts("Playing some file")
        event = SwitchX.execute(conn, uuid, "playback", "ivr/ivr-welcome_to_freeswitch.wav")
        IO.puts("Playback duration was #{event.headers["variable_playback_ms"]} ms")

        message = SwitchX.Event.Headers.new(%{
          "call-command": "hangup",
          "hangup-cause": "NORMAL_CLEARING",
        }) |> SwitchX.Event.new()

        IO.puts("Bye")
        SwitchX.send_message(conn, uuid, message)
        SwitchX.exit(conn)

        :ok
      {:error, term} -> "Error #{term}"
    end
  end
end

