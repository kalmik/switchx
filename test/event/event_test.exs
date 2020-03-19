defmodule SwitchX.Event.Test do
  use ExUnit.Case, async: true

  test "Parsing auth/request" do
    message = "Content-Type: auth/request\n\n"

    assert %SwitchX.Event{
             body: "",
             headers: %{
               "Content-Type" => "auth/request"
             }
           } = SwitchX.Event.new(message)
  end

  test "Parsing text/switchx.event-plain BACKGROUND_JOB" do
    message = """
    Content-Length: 625
    Content-Type: text/event-plain

    Job-UUID: 7f4db78a-17d7-11dd-b7a0-db4edd065621
    Job-Command: originate
    Job-Command-Arg: sofia/default/1005%20'%26park'
    Event-Name: BACKGROUND_JOB
    Core-UUID: 42bdf272-16e6-11dd-b7a0-db4edd065621
    FreeSWITCH-Hostname: ser
    FreeSWITCH-IPv4: 192.168.1.104
    FreeSWITCH-IPv6: 127.0.0.1
    Event-Date-Local: 2008-05-02%2007%3A37%3A03
    Event-Date-GMT: Thu,%2001%20May%202008%2023%3A37%3A03%20GMT
    Event-Date-timestamp: 1209685023894968
    Event-Calling-File: mod_event_socket.c
    Event-Calling-Function: api_exec
    Event-Calling-Line-Number: 609
    Content-Length: 41

    +OK 7f4de4bc-17d7-11dd-b7a0-db4edd065621
    """

    assert %SwitchX.Event{
             body: "+OK 7f4de4bc-17d7-11dd-b7a0-db4edd065621\n",
             headers: %{
               "Content-Length" => "41",
               "Content-Type" => "text/event-plain",
               "Core-UUID" => "42bdf272-16e6-11dd-b7a0-db4edd065621",
               "Event-Calling-File" => "mod_event_socket.c",
               "Event-Calling-Function" => "api_exec",
               "Event-Calling-Line-Number" => "609",
               "Event-Date-GMT" => "Thu, 01 May 2008 23:37:03 GMT",
               "Event-Date-Local" => "2008-05-02 07:37:03",
               "Event-Date-timestamp" => "1209685023894968",
               "Event-Name" => "BACKGROUND_JOB",
               "FreeSWITCH-Hostname" => "ser",
               "FreeSWITCH-IPv4" => "192.168.1.104",
               "FreeSWITCH-IPv6" => "127.0.0.1",
               "Job-Command" => "originate",
               "Job-Command-Arg" => "sofia/default/1005 '&park'",
               "Job-UUID" => "7f4db78a-17d7-11dd-b7a0-db4edd065621"
             }
           } = SwitchX.Event.new(message)
  end

  test "Parse disconnect message" do
    message = """
    Content-Type: text/disconnect-notice
    Content-Length: 67

    Disconnected, goodbye.
    See you at ClueCon! http://www.cluecon.com/
    """

    assert %SwitchX.Event{
             body: "Disconnected, goodbye.\nSee you at ClueCon! http://www.cluecon.com/\n",
             headers: %{
               "Content-Length" => "67",
               "Content-Type" => "text/disconnect-notice"
             }
           } = SwitchX.Event.new(message)
  end

  test "Given an SwitchX.Event dump it into a String" do
    message = """
    Content-Length: 41
    Content-Type: text/event-plain
    Core-UUID: 42bdf272-16e6-11dd-b7a0-db4edd065621
    Event-Calling-File: mod_event_socket.c
    Event-Calling-Function: api_exec
    Event-Calling-Line-Number: 609
    Event-Date-GMT: Thu,%2001%20May%202008%2023:37:03%20GMT
    Event-Date-Local: 2008-05-02%2007:37:03
    Event-Date-timestamp: 1209685023894968
    Event-Name: BACKGROUND_JOB
    FreeSWITCH-Hostname: ser
    FreeSWITCH-IPv4: 192.168.1.104
    FreeSWITCH-IPv6: 127.0.0.1
    Job-Command: originate
    Job-Command-Arg: sofia/default/1005%20'&park'
    Job-UUID: 7f4db78a-17d7-11dd-b7a0-db4edd065621

    +OK 7f4de4bc-17d7-11dd-b7a0-db4edd065621
    """

    event = %SwitchX.Event{
      body: "+OK 7f4de4bc-17d7-11dd-b7a0-db4edd065621\n",
      headers: %{
        "Content-Length" => 41,
        "Content-Type" => "text/event-plain",
        "Core-UUID" => "42bdf272-16e6-11dd-b7a0-db4edd065621",
        "Event-Calling-File" => "mod_event_socket.c",
        "Event-Calling-Function" => "api_exec",
        "Event-Calling-Line-Number" => "609",
        "Event-Date-GMT" => "Thu, 01 May 2008 23:37:03 GMT",
        "Event-Date-Local" => "2008-05-02 07:37:03",
        "Event-Date-timestamp" => "1209685023894968",
        "Event-Name" => "BACKGROUND_JOB",
        "FreeSWITCH-Hostname" => "ser",
        "FreeSWITCH-IPv4" => "192.168.1.104",
        "FreeSWITCH-IPv6" => "127.0.0.1",
        "Job-Command" => "originate",
        "Job-Command-Arg" => "sofia/default/1005 '&park'",
        "Job-UUID" => "7f4db78a-17d7-11dd-b7a0-db4edd065621"
      }
    }

    assert message == SwitchX.Event.dump(event)
  end
end
