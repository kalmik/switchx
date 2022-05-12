defmodule SwitchX.Event do
  @behaviour Access

  defstruct headers: Map.new(),
            body: ""

  ## Access CALLBACKS ##

  def fetch(body, key),
    do: Map.fetch(body.headers, key)

  def get(body, key, default),
    do: Map.get(body.headers, key, default)

  def get_and_update(body, key, fun),
    do: Map.get(body.headers, key, fun)

  def pop(body, key),
    do: Map.get(body.headers, key)

  @spec new() :: SwitchX.Event
  def new(), do: %__MODULE__{}
  def new(""), do: new()

  @doc """
  Create a Event from a plain message from freeswitch,
  """
  @spec new(message :: String) :: SwitchX.Event
  def new(message) when is_binary(message) do
    message
    |> String.split("\n\n")
    |> Enum.flat_map(&String.split(&1, "\n"))
    |> Enum.split_while(fn line ->
      case String.split(line, ": ", parts: 2) do
        [_k, _v] -> true
        _ -> false
      end
    end)
    |> SwitchX.Event.build()
  end

  @spec new(headers :: SwitchX.Event.Header) :: SwitchX.Event
  def new(headers), do: new(headers, "")

  @doc """
  Given a SwichX.Event.Headers and a body string create a new Event
  """
  @spec new(headers :: SwitchX.Event.Header, body :: String) :: SwitchX.Event
  def new(headers, body) do
    %__MODULE__{
      headers: headers.data,
      body: body
    }
  end

  @doc """
  Updates a SwitchX.Event with another event message and body, see Map.merge/2
  """
  @spec merge(event :: SwitchX.Event, new :: SwitchX.Event) :: SwitchX.Event
  def merge(event, new) do
    event = put_in(event.headers, Map.merge(event.headers, new.headers))
    put_in(event.body, event.body <> new.body)
  end

  @doc false
  def build({headers, body}) do
    %__MODULE__{
      headers: SwitchX.Event.Headers.new(headers).data,
      body: Enum.join(body, "\n")
    }
  end

  @doc """
  Dumps a SwitchX.Event into a string URI encoded

  Returns
  ```
    event_string
  ```

  ## Example

      iex> SwitchX.Event.new(SwitchX.Event.Headers.new(%{foo: "bar 53"}), "body")
           |> SwitchX.Event.dump()

      "foo: bar%2053

      body"
  """
  @spec dump(event :: SwitchX.Event) :: event_string :: String
  def dump(event) do
    h_part =
      Enum.map(event.headers, fn {h, v} ->
        String.trim("#{h}: #{URI.encode("#{v}")}", "\n")
      end)
      |> Enum.join("\n")

    case event.body do
      nil -> "#{h_part}\n\n"
      "" -> "#{h_part}\n\n"
      body -> "#{h_part}\n\n#{URI.encode(body)}"
    end
    |> String.trim("\n\n")
  end
end
