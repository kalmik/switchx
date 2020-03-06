defmodule SwitchX do
  ## API ##

  @doc """
  Tells FreeSWITCH not to close the socket connection when a channel hangs up.
  Instead, it keeps the socket connection open until the last event related
  to the channel has been received by the socket client.

  Returns
  ```
    {:ok, "Lingering"}
  ```

  ## Examples

      iex> SwitchX.linger(context.conn)
      {:ok, "Lingering"}
  """
  @spec linger(conn :: Pid) :: term
  def linger(conn), do: :gen_statem.call(conn, {:linger})

  @doc """
  Reply the auth/request package from FreeSWITCH.

  Returns
  ```
    {:ok, "Accepted"} | {:error, "Denied"}
  ```

  ## Examples
      iex> SwitchX.auth(conn, "ClueCon")
      {:ok, "Accepted"}

      iex> SwitchX.auth(conn, "Incorrect")
      {:error, "Denied"}
  """
  @spec auth(conn :: Pid, password :: String) :: {:ok, term} | {:error, term}
  def auth(conn, password), do: :gen_statem.call(conn, {:auth, password})

  @doc """
  Send a FreeSWITCH API command.

  Returns
  ```
    {:ok, term}
  ```

  ## Examples

      iex> SwitchX.api(
            conn,
            "uuid_getvar a1024ff5-a5b3-4c0a-abd3-fd4a89508b5b current_application"
           )
      %SwitchX.Event{
        body: "park",
        headers: %{"Content-Length" => "4", "Content-Type" => "api/response"}
      }
  """
  @spec api(conn :: Pid, args :: String) :: {:ok, term}
  def api(conn, args), do: :gen_statem.call(conn, {:api, args})

  @doc """
  Enable or disable events by class or all.

  Returns
  ```
    :ok
  ```

  ## Examples

      iex> SwitchX.listen_event(conn, "BACKGROUND_JOB")
      :ok
  """
  @spec listen_event(conn :: Pid, event_name :: String) :: :ok
  def listen_event(conn, event_name), do: :gen_statem.call(conn, {:listen_event, event_name})

  def originate(conn, aleg, bleg, :expand) do
    perform_originate(conn, "expand originate #{aleg} #{bleg}")
  end

  def originate(conn, aleg, bleg) do
    perform_originate(conn, "originate #{aleg} #{bleg}")
  end

  defp perform_originate(conn, command) do
    {:ok, response} = api(conn, command)

    parsed_body =
      response.body
      |> String.trim("\n")
      |> String.split(" ", parts: 2)

    case parsed_body do
      ["-ERR", term] -> {:error, term}
      ["+OK", uuid] -> {:ok, uuid}
      _ -> {:error, :unknown}
    end
  end
end
