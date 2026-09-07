%% N01 bounded read-only I/O only. State interpretation belongs to Gleam.
%% Fixed endpoints, no shell, redirects/proxies/curl configuration disabled.
-module(uos_peer_http_ffi).
-export([probe/1]).

-define(LIMIT, 33792).
-define(DEADLINE_MS, 7000).

probe(Url) when Url =:= <<"http://vm-1.tail55d152.ts.net:4100/api/health">>;
                Url =:= <<"http://vm-1.tail55d152.ts.net:8088/api/health">> ->
    case os:find_executable("curl") of
        false -> {error, <<"curl unavailable">>};
        Executable ->
            Parent = self(),
            Ref = make_ref(),
            {Pid, Mon} = spawn_monitor(fun() ->
                Parent ! {Ref, bounded_probe(Executable, Url)}
            end),
            receive
                {Ref, Result} -> erlang:demonitor(Mon, [flush]), Result;
                {'DOWN', Mon, process, Pid, _} -> {error, <<"probe worker failed">>}
            after ?DEADLINE_MS + 500 ->
                exit(Pid, kill),
                receive {'DOWN', Mon, process, Pid, _} -> ok end,
                receive {Ref, _} -> ok after 0 -> ok end,
                {error, <<"probe worker deadline">>}
            end
    end;
probe(_) -> {error, <<"endpoint is not allowlisted">>}.

bounded_probe(Executable, Url) ->
    Args = ["--disable", "--proto", "=http", "--noproxy", "*",
            "--connect-timeout", "2", "--max-time", "5",
            "--max-filesize", "32768", "--silent", "--show-error",
            "--write-out", "\n__UOS_HTTP__%{http_code}\n", binary_to_list(Url)],
    try open_port({spawn_executable, Executable},
                  [binary, use_stdio, stderr_to_stdout, exit_status, hide, {args, Args}]) of
        Port ->
            Deadline = erlang:monotonic_time(millisecond) + ?DEADLINE_MS,
            try collect(Port, Deadline, <<>>) after
                case erlang:port_info(Port) of
                    undefined -> ok;
                    _ -> erlang:port_close(Port)
                end
            end
    catch
        error:_ -> {error, <<"cannot start bounded HTTP probe">>}
    end.

collect(Port, Deadline, Bytes) ->
    Left = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Chunk}} when byte_size(Bytes) + byte_size(Chunk) =< ?LIMIT ->
            collect(Port, Deadline, <<Bytes/binary, Chunk/binary>>);
        {Port, {data, _}} -> {error, <<"response quota exceeded">>};
        {Port, {exit_status, Exit}} -> decode(Exit, Bytes)
    after Left -> {error, <<"HTTP probe deadline">>}
    end.

decode(Exit, Bytes) ->
    Marker = <<"\n__UOS_HTTP__">>,
    Time = erlang:system_time(millisecond),
    case binary:matches(Bytes, Marker) of
        [] -> {ok, {Exit, 0, <<>>, Time}};
        Matches ->
            {Pos, Len} = lists:last(Matches),
            Body = binary:part(Bytes, 0, Pos),
            Tail = binary:part(Bytes, Pos + Len, byte_size(Bytes) - Pos - Len),
            case Tail of
                <<A, B, C, "\n">> when A >= $0, A =< $9, B >= $0, B =< $9,
                                          C >= $0, C =< $9 ->
                    {ok, {Exit, (A-$0)*100 + (B-$0)*10 + C-$0, Body, Time}};
                _ -> {error, <<"malformed HTTP status trailer">>}
            end
    end.
