defmodule SwitchX.Event.Headers do
  @behaviour Access

  @moduledoc """
  This Module defines a struct for an ESL event Headers.

  The freeswitch ESL event implementation commonly contains headers
  with a mapped key-value text as:

  Event-Name: CUSTOM
  variable_caller_id_name: caller
  variable_caller_id_number: 9494
  ...
  """

  defstruct data: Map.new()

  @doc """
  Create a Event header from a enumerable,
  if it has duplicated mappable keys the latest one prevails.
  """
  def new([]), do: %__MODULE__{}

  def new(headers) do
    headers
    |> Enum.map(fn line -> String.split(line, ": ", parts: 2) end)
    |> Enum.into(%__MODULE__{})
  end

  ## Access CALLBACKS ##

  def fetch(body, key),
    do: Map.fetch(body.data, key)

  def get(body, key, default),
    do: Map.get(body.data, key, default)

  def get_and_update(body, key, fun),
    do: Map.get(body.data, key, fun)

  def pop(body, key),
    do: Map.get(body.data, key)

  defp uri_decode(nil), do: nil

  defp uri_decode(value) when is_binary(value) do
    try do
      URI.decode(value)
    rescue
      ArgumentError -> value
    end
  end

  defp uri_decode(value), do: value

  @doc """
  Collectable callback to describe how the data must be stored
  """
  def collect(event_body, term) do
    case term do
      {:cont, [key, value]} ->
        put_in(event_body.data, Map.put(event_body.data, key, uri_decode(value)))

      {:cont, _} ->
        event_body

      :done ->
        event_body

      :halt ->
        :ok
    end
  end
end

defimpl Collectable, for: SwitchX.Event.Headers do
  def into(original) do
    {original, &SwitchX.Event.Headers.collect/2}
  end
end
