defmodule Examples.OutboundSocket do
  def init() do
    {:ok, conn} = SwitchX.Connection.Outbound.start_link([mod: Examples.OutboundSession, host: "127.0.0.1", port: 9998])
  end
end

defmodule Examples.OutboundSession do
  @behavior :gen_statem

  defstruct [
    :conn
  ]

  def start_link(conn), do: :gen_statem.start_link(__MODULE__, [conn], [])
  def init([conn]) do
    data = %__MODULE__{
      conn: conn
    }

    {:ok, :waiting_data, data}
  end

  def callback_mode() do
    :state_functions
  end

  def waiting_data(:info, {:switchx_event, event}, data) do
    IO.inspect(event)
    {:next_state, :ready, data}
  end

  def ready(:info, {:switchx_event, event}, data) do
    IO.inspect(event)
    {:keep_state, data}
  end
end

