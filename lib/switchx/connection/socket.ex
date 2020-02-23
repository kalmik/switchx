defmodule SwitchX.Connection.Socket do
  @type switchx_event :: SwitchX.Event.new()

  @moduledoc """
  This modules provide to work with FreeSWITCH ESL socket
  """

  @doc """
  Given a port and a initial payload continues reading until it gets a full parsed
  SwitchX.Event.
  """
  @spec recv(socket :: Port, payload :: String) :: switchx_event
  def recv(socket, payload \\ "") when is_binary(payload) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      # Initial header fully read, parsing event
      {:error, :timeout} ->
        read_body(socket, SwitchX.Event.new(payload))

      {:ok, "\n"} ->
        read_body(socket, SwitchX.Event.new(payload))

      # Initial header fully read, parsing event
      {:ok, data} ->
        recv(socket, payload <> data)
    end
  end

  @doc """
  Given a parsed initial event check if there is body to be read, and read them all.
  """
  @spec read_body(socket :: Port, event :: switchx_event) :: switchx_event
  defp read_body(socket, event) do
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
