defmodule SwitchX do
  ## API ##

  def auth(conn, password), do: :gen_statem.call(conn, {:auth, password})
  def api(conn, args), do: :gen_statem.call(conn, {:api, args})
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
