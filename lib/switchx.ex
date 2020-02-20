defmodule SwitchX do

  ## API ##

  def auth(conn, password), do: :gen_statem.call(conn, {:auth, password})
  def api(conn, args), do: :gen_statem.call(conn, {:api, args})
  def listen_event(conn, event_name), do: :gen_statem.call(conn, {:listen_event, event_name})

end
