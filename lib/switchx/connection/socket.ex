defmodule SwitchX.Connection.Socket do
  @moduledoc false
  @type switchx_event :: SwitchX.Event.new()

  require Logger
  @doc """
  Given a port and a initial payload continues reading until it gets a full parsed
  SwitchX.Event.
  """
  @spec recv(socket :: Port, payload :: String) :: switchx_event
  def recv(socket, payload \\ "") when is_binary(payload) do
    :inet.setopts(socket, packet: :line)

    case :gen_tcp.recv(socket, 0, 1_000) do
      # Socket has closed, parsing data until now
      {:error, :closed} ->
        SwitchX.Event.new(payload)

      # Initial header fully read, parsing event
      {:error, :timeout} ->
        Logger.info("SwitchXSock timeout with payload: #{inspect payload}")
        read_body(socket, SwitchX.Event.new(payload))

      {:ok, "\n"} ->
        Logger.info("SwitchXSock end line with payload: #{inspect payload}")
        read_body(socket, SwitchX.Event.new(payload))

      {:ok, data} ->
        Logger.info("SwitchXSock continue read with payload: #{inspect payload}")
        recv(socket, payload <> data)
    end
  end

  @spec read_body(socket :: Port, event :: switchx_event) :: switchx_event
  defp read_body(socket, event) do
    content_length = String.to_integer(Map.get(event.headers, "Content-Length", "0"))

    Logger.info("SwitchXSock read_body with len #{content_length} read with event: #{inspect event}")

    if content_length > 0 do
      :inet.setopts(socket, packet: :raw)

      packet =
        case :gen_tcp.recv(socket, content_length, 1_000) do
          {:error, :timeout} -> ""
          {:ok, packet} -> packet
        end

      Logger.info("SwitchXSock read_body after last recv packet: #{inspect packet}")

      :inet.setopts(socket, packet: :line)
      SwitchX.Event.merge(event, SwitchX.Event.new(packet))
    else
      event
    end
  end
end
