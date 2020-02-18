defmodule SwitchX.Event do
  defstruct headers: Map.new(),
            body: ""

  @doc """
  Create a Event from a plain message from freeswitch,
  """
  def new(), do: %__MODULE__{}
  def new(""), do: new()

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

  def new({headers, body}) do
    %__MODULE__{
      headers: SwitchX.Event.Headers.new(headers).data,
      body: Enum.join(body, "\n")
    }
  end

  def merge(event, new) do
    event = put_in(event.headers, Map.merge(event.headers, new.headers))
    put_in(event.body, event.body <> new.body)
  end

  def append_body(event, body), do: put_in(event.body, event.body <> body)
end
