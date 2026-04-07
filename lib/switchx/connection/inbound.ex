defmodule SwitchX.Connection.Inbound do
  @moduledoc """
  Provides an abstraction to a FreeSWITCH inbound connection

  Inbound mode means you run your applications as clients,
  and connect to the FreeSWITCH server to invoke commands and control FreeSWITCH.
  """

  require Logger

  @mode :inbound
  @socket_opts [:binary, active: :once, packet: :line]
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

  # added socket to the return tuple in a successful connection
  def start(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)

    case perform_connect(host, port, @socket_opts, @timeout) do
      {:ok, socket} ->
        {:ok, client} = SwitchX.Connection.start_link(self(), socket, @mode)
        :gen_tcp.controlling_process(socket, client)
        {:ok, client, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def close(client, socket) do
    Logger.info("Closing gen_tcp connection")
    :gen_tcp.close(socket)
    :gen_statem.stop(client)
  end

  defp perform_connect(host, port, socket_opts, timeout) when is_binary(host) do
    # Try to parse as an IP address first, otherwise treat as hostname
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip_tuple} ->
        :gen_tcp.connect(ip_tuple, port, socket_opts, timeout)

      {:error, :einval} ->
        # Not a valid IP address, treat as hostname (charlist format)
        :gen_tcp.connect(String.to_charlist(host), port, socket_opts, timeout)
    end
  end

  defp perform_connect(host, port, socket_opts, timeout) when is_tuple(host) do
    :gen_tcp.connect(host, port, socket_opts, timeout)
  end
end
