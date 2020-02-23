defmodule SwitchX.Connection.Socket do
  @moduledoc """
  This modules provide to work with FreeSWITCH ESL socket
  """

  @doc """
  Given a port and a initial payload continues reading until it gets a full parsed
  SwitchX.Event
  """
  @spec recv(socket :: Port, payload :: String) :: SwitchX.Event.new()
  def recv(socket, payload \\ "") when is_binary(payload) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, "\n"} -> read_to_event(socket, SwitchX.Event.new(payload))
      {:ok, data} -> recv(socket, payload <> data)
    end
  end

  defp read_to_event(socket, event) do
    content_length = String.to_integer(Map.get(event.headers, "Content-Length", "0"))

    if content_length > 0 do
      :inet.setopts(socket, packet: :raw)

      packet =
        case :gen_tcp.recv(socket, content_length, 1_000) do
          {:error, :timeout} -> ""
          {:ok, packet} -> packet
        end

      :inet.setopts(socket, packet: :line)
      SwitchX.Event.merge(event, SwitchX.Event.new(packet))
    else
      event
    end
  end
end
