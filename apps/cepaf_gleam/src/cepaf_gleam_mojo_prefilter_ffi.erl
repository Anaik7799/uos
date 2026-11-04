-module(cepaf_gleam_mojo_prefilter_ffi).
-export([open_port/2, send_packet/2, receive_packet_timeout/2, reap_process_tree/1, close_port/1]).

open_port(Cmd, Args) ->
    Bin = unicode:characters_to_list(Cmd),
    ArgList = [unicode:characters_to_list(A) || A <- Args],
    try
        Port = erlang:open_port({spawn_executable, Bin}, [
            {args, ArgList},
            binary,
            use_stdio,
            exit_status,
            {packet, 4}
        ]),
        {ok, Port}
    catch
        Class:Reason ->
            ErrStr = io_lib:format("~p:~p", [Class, Reason]),
            {error, unicode:characters_to_binary(lists:flatten(ErrStr))}
    end.

send_packet(Port, Packet) when is_port(Port), is_bitstring(Packet) ->
    try
        erlang:port_command(Port, Packet),
        {ok, nil}
    catch
        Class:Reason ->
            ErrStr = io_lib:format("send_failed:~p:~p", [Class, Reason]),
            {error, unicode:characters_to_binary(lists:flatten(ErrStr))}
    end.

receive_packet_timeout(Port, TimeoutMs) when is_port(Port), is_integer(TimeoutMs) ->
    receive
        {Port, {data, Data}} ->
            {ok, Data};
        {Port, {exit_status, Status}} ->
            {error, unicode:characters_to_binary(io_lib:format("port_exited:~p", [Status]))}
    after TimeoutMs ->
        reap_process_tree(Port),
        {error, <<"timeout_deadline_exceeded">>}
    end.

reap_process_tree(Port) when is_port(Port) ->
    case erlang:port_info(Port, os_pid) of
        {os_pid, OsPid} when is_integer(OsPid), OsPid > 0 ->
            os:cmd(lists:flatten(io_lib:format("pkill -9 -P ~p 2>/dev/null; kill -9 ~p 2>/dev/null", [OsPid, OsPid]))),
            catch erlang:port_close(Port),
            {ok, nil};
        _ ->
            catch erlang:port_close(Port),
            {ok, nil}
    end;
reap_process_tree(_) ->
    {ok, nil}.

close_port(Port) when is_port(Port) ->
    catch erlang:port_close(Port),
    nil;
close_port(_) ->
    nil.
