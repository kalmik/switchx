defmodule SwitchX.Event do
  defstruct headers: Map.new(),
            body: ""

  @doc """
  Create a Event from a plain message from freeswitch,
  """
  @spec new() :: SwitchX.Event
  def new(), do: %__MODULE__{}
  def new(""), do: new()

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
    |> SwitchX.Event.new()
  end

  @spec new({headers :: SwitchX.Event.Header, body :: String}) :: SwitchX.Event
  def new({headers, body}) do
    %__MODULE__{
      headers: SwitchX.Event.Headers.new(headers).data,
      body: Enum.join(body, "\n")
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
        "#{h}: #{if is_binary(v), do: URI.encode(v), else: v}"
      end)
      |> Enum.join("\n")

    "#{h_part}\n\n#{event.body}"
  end
end
