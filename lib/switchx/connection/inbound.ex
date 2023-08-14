defmodule SwitchX.Connection.Inbound do
  @moduledoc """
  Provides an abstraction to a FreeSWITCH inbound connection

  Inbound mode means you run your applications as clients,
  and connect to the FreeSWITCH server to invoke commands and control FreeSWITCH.
  """
  @mode :inbound
  @socket_opts [:binary, active: :once, packet: :line, keepalive: true]
  @timeout 5_000

  @doc """
  Starts a new inbond connection.

  Returns `{:ok, Pid}`

  ## Examples

      iex> paramaters = [
        host: "127.0.0.1",
        port: 8021,
      ]

      iex> SwitchX.Connection.Inbound.start_link(paramaters)
      {:ok, connection_pid}

  """
  def start_link(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)

    case perform_connect(host, port, @socket_opts, @timeout) do
      {:ok, socket} ->
        {:ok, client} = SwitchX.Connection.start_link(self(), socket, @mode)
        :gen_tcp.controlling_process(socket, client)
        {:ok, client}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_connect(host, port, socket_opts, timeout) when is_binary(host) do
    perform_connect(String.to_charlist(host), port, socket_opts, timeout)
  end

  defp perform_connect(host, port, socket_opts, timeout) when is_tuple(host) or is_list(host) do
    :gen_tcp.connect(host, port, socket_opts, timeout)
  end
end
