-module(mcp_stdio_ffi).
-export([read_line/0, with_gateway_boot_lock/1, register_or_stop_supervisor/1,
         loaded_mcp_beams_digest/0, run_workspace_bounded_cd/4,
         with_private_route_lock/1, start_zenoh_sse_subscriber/7,
         with_zenoh_boot_lock/1, isolate_zenoh_supervisor_start/1, register_or_keep_zenoh_supervisor/1,
         zenoh_supervisor_running/0, zenoh_subscriber_state/0,
         zenoh_subscriber_last_activity_age_ms/0,
         stop_zenoh_sse_subscriber/1, zenoh_subscriber_alive/0, zenoh_sse_loopback_fixture/4,
         mark_stdio_gateway/0, stdio_gateway/0,
         zenoh_sse_registered_health_fixture/1,
         zenoh_sse_registered_isolation_fixture/3, zenoh_sse_stdio_guard_fixture/2, zenoh_test_environment/1, zenoh_sse_handshake_fixture/0, zenoh_sse_atomics_fixture/1]).

-include_lib("kernel/include/file.hrl").

-define(MAX_LINE_BYTES, 1048576).
-define(OUTPUT_LIMIT, 1048576).
-define(UNOBSERVED_ACTIVITY, -9223372036854775808).

%% io:get_line/1 returns a character list under the default standard_io
%% configuration and a binary when binary mode is enabled. Normalize both
%% without changing global IO options, and reject oversized request frames.
read_line() ->
    case io:get_line("") of
        eof -> end_of_file;
        {error, Reason} -> {read_error, reason_binary(Reason)};
        Data -> normalize_line(Data)
    end.

normalize_line(Data) when is_binary(Data) -> bounded_line(Data);
normalize_line(Data) when is_list(Data) ->
    case unicode:characters_to_binary(Data) of
        Binary when is_binary(Binary) -> bounded_line(Binary);
        {error, _, _} -> {read_error, <<"stdin line is not valid Unicode">>};
        {incomplete, _, _} -> {read_error, <<"stdin line has incomplete Unicode">>}
    end;
normalize_line(_) -> {read_error, <<"stdin returned an unsupported value">>}.

bounded_line(Binary) when byte_size(Binary) =< ?MAX_LINE_BYTES -> {line, Binary};
bounded_line(_) -> {read_error, <<"stdin line exceeds 1048576-byte limit">>}.

reason_binary(Reason) ->
    unicode:characters_to_binary(io_lib:format("~p", [Reason])).

with_gateway_boot_lock(Fun) ->
    global:trans({uos_mcp_runtime_gateway_boot_lock, self()}, fun() -> Fun() end).

%% Only private caller processes acquire this lock. The gateway mailbox and
%% public ingress never acquire it. global releases it if the caller dies.
with_private_route_lock(Fun) ->
    global:trans({uos_mcp_private_routes, self()}, fun() -> Fun() end).

register_or_stop_supervisor(Pid) ->
    case erlang:whereis(uos_mcp_runtime_gateway_sup) of
        Pid -> true;
        Existing when is_pid(Existing), Existing =/= Pid ->
            case erlang:is_process_alive(Existing) of
                true ->
                    try erlang:unlink(Pid) catch _:_ -> ok end,
                    try gen_server:stop(Pid, shutdown, 1000) catch _:_ -> ok end,
                    try exit(Pid, shutdown) catch _:_ -> ok end,
                    false;
                false -> register_supervisor(Pid)
            end;
        _ -> register_supervisor(Pid)
    end.

register_supervisor(Pid) ->
    try
        erlang:register(uos_mcp_runtime_gateway_sup, Pid),
        true
    catch
        error:badarg ->
            try erlang:unlink(Pid) catch _:_ -> ok end,
            try exit(Pid, shutdown) catch _:_ -> ok end,
            false
    end.

%% The executable/guardian belong to the loaded capsule, while the child cwd
%% belongs to the caller's workspace (or an isolated absolute test directory).
%% This adapter is internal to the gateway; it grants no tool/effect authority.
run_workspace_bounded_cd(Path, Args, Cwd, TimeoutMs)
  when is_binary(Path), is_list(Args), is_binary(Cwd),
       is_integer(TimeoutMs), TimeoutMs > 0, TimeoutMs =< 60000 ->
    try
        CwdList = utf8_chars(Cwd),
        absolute = filename:pathtype(CwdList),
        Parts = filename:split(CwdList),
        false = lists:member("..", Parts),
        RealCwd = filename:join(Parts),
        true = filelib:is_dir(RealCwd),
        CapRoot = utf8_chars(ecology_capability_ffi:uos_root()),
        Ocaml = workspace_ocaml(CapRoot),
        Guardian = filename:join(CapRoot, "tools/ecology_process.ml"),
        true = filelib:is_regular(Guardian),
        A = ["-I", "+unix", Guardian, integer_to_list(TimeoutMs),
             integer_to_list(?OUTPUT_LIMIT), "merged", utf8_chars(Path)] ++
            [utf8_chars(Argument) || Argument <- Args],
        Port = erlang:open_port({spawn_executable, Ocaml},
          [stream, use_stdio, exit_status, binary, {args, A}, {cd, RealCwd}]),
        collect_workspace(Port,
          erlang:monotonic_time(millisecond) + TimeoutMs + 1000, 0, [])
    catch
        _:_ -> {error, <<"backend_spawn_failed">>}
    end;
run_workspace_bounded_cd(_, _, _, _) -> {error, <<"invalid_resource_bound">>}.

utf8_chars(Bytes) when is_binary(Bytes) ->
    case unicode:characters_to_list(Bytes, utf8) of
        Chars when is_list(Chars) -> Chars;
        _ -> error(invalid_utf8)
    end.

workspace_ocaml(CapRoot) ->
    Manifest = filename:join(CapRoot, "runtime-dependencies.json"),
    case filelib:is_regular(Manifest) of
        false -> filename:join(CapRoot, "toolchains/opam-ocaml/bin/ocaml");
        true ->
            {ok, #file_info{type = regular, size = N}} = file:read_file_info(Manifest),
            true = N =< 65536,
            {ok, Body} = file:read_file(Manifest),
            #{<<"ocaml">> := #{<<"path">> := Path, <<"sha256">> := Expected}} =
                json:decode(Body),
            Ocaml = utf8_chars(Path),
            absolute = filename:pathtype(Ocaml),
            {ok, #file_info{type = regular, size = Size}} = file:read_file_info(Ocaml),
            true = Size =< 134217728,
            {ok, Fd} = file:open(Ocaml, [read, binary, raw]),
            Actual = try hash_workspace_dependency(Fd, crypto:hash_init(sha256), Size)
                     after file:close(Fd) end,
            true = Actual =:= Expected,
            Ocaml
    end.

hash_workspace_dependency(Fd, Hash, Remaining) ->
    case file:read(Fd, 65536) of
        eof when Remaining =:= 0 ->
            binary:encode_hex(crypto:hash_final(Hash), lowercase);
        {ok, Bytes} when byte_size(Bytes) =< Remaining ->
            hash_workspace_dependency(Fd,
              crypto:hash_update(Hash, Bytes), Remaining - byte_size(Bytes));
        _ -> error(dependency_changed)
    end.

collect_workspace(Port, Deadline, Size, Chunks) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Chunk}} ->
            case Size + byte_size(Chunk) =< ?OUTPUT_LIMIT of
                true -> collect_workspace(Port, Deadline,
                          Size + byte_size(Chunk), [Chunk | Chunks]);
                false ->
                    try erlang:port_close(Port) catch _:_ -> ok end,
                    {error, <<"output_limit">>}
            end;
        {Port, {exit_status, 124}} -> {error, <<"timeout">>};
        {Port, {exit_status, 125}} -> {error, <<"backend_output_or_process_failure">>};
        {Port, {exit_status, Code}} ->
            {ok, {Code, iolist_to_binary(lists:reverse(Chunks))}}
    after Remaining ->
        try erlang:port_close(Port) catch _:_ -> ok end,
        {error, <<"guardian_timeout">>}
    end.

loaded_mcp_beams_digest() ->
    Modules = [cepaf_gleam@mcp@registry, cepaf_gleam@mcp@admission,
               cepaf_gleam@mcp@receipts, cepaf_gleam@mcp@dispatch,
               cepaf_gleam@mcp@route_convergence, cepaf_gleam@mcp@server,
               cepaf_gleam@mcp@runtime_gateway],
    try
        Acc = lists:foldl(fun(Mod, Bytes) ->
            {module, Mod} = code:ensure_loaded(Mod),
            {file, _} = code:is_loaded(Mod),
            Md5 = Mod:module_info(md5),
            true = is_binary(Md5) andalso byte_size(Md5) =:= 16,
            Name = atom_to_binary(Mod, utf8),
            <<Bytes/binary, (byte_size(Name)):32/unsigned-big, Name/binary,
              (byte_size(Md5)):32/unsigned-big, Md5/binary>>
        end, <<>>, Modules),
        binary:encode_hex(crypto:hash(sha256, Acc), lowercase)
    catch
        _:_ -> <<"unobserved">>
    end.

%% Dedicated MCP-only SSE child. Passive bounded TCP never uses proxy settings,
%% redirects, the general Zenoh client, or an input-selected destination.
with_zenoh_boot_lock(Fun) ->
    global:trans({uos_mcp_zenoh_boot_lock, self()}, Fun).

zenoh_supervisor_running() ->
    case whereis(uos_mcp_zenoh_sup) of
        P when is_pid(P) -> is_process_alive(P);
        _ -> false
    end.

register_or_keep_zenoh_supervisor(Pid) ->
    unlink(Pid),
    case whereis(uos_mcp_zenoh_sup) of
        Pid -> true;
        _ ->
            try register(uos_mcp_zenoh_sup, Pid), true
            catch error:badarg ->
                try gen_server:stop(Pid, shutdown, 1000)
                catch _:_ -> exit(Pid, kill) end,
                zenoh_supervisor_running()
            end
    end.

start_zenoh_sse_subscriber(Host, Port, Secret, Register, LockPort, Idle, Handler)
  when (Host =:= <<"nas-1.tail55d152.ts.net">> orelse Host =:= <<"127.0.0.1">>),
       is_integer(Port), Port > 0, Port =< 65535,
       is_binary(Secret), byte_size(Secret) > 0, is_boolean(Register),
       is_integer(LockPort), LockPort >= 0, LockPort =< 65535,
       is_integer(Idle), Idle > 0, Idle =< 60000, is_function(Handler, 1) ->
    Parent = self(), Tag = make_ref(),
    {Pid, MonRef} = spawn_monitor(fun() ->
        ParentMon = monitor(process, Parent),
        case sse_register(Register) of
            false -> Parent ! {Tag, {error, <<"subscriber_already_active">>}};
            true ->
                case sse_lock(LockPort) of
                    {error, _} ->
                        sse_unregister(Register),
                        Parent ! {Tag, {error, <<"subscriber_already_active">>}};
                    {ok, LockSocket} ->
                        Meta = sse_meta_init(Register, Idle),
                        try
                            Parent ! {Tag, ok},
                            receive
                                {Tag, linked} ->
                                    demonitor(ParentMon, [flush]),
                                    Parent ! {Tag, linked_ack},
                                    sse_reconnect(Host, Port, Handler, Meta, Idle);
                                {'DOWN', ParentMon, process, Parent, _} -> ok
                            after 1000 -> ok end
                        after
                            sse_meta(Meta, false, Idle),
                            sse_close_lock(LockSocket),
                            sse_unregister(Register)
                        end
                end
        end
    end),
    sse_await_start(Pid, MonRef, Tag);
start_zenoh_sse_subscriber(_, _, _, _, _, _, _) ->
    {error, <<"invalid_zenoh_subscriber_endpoint_or_secret">>}.

sse_await_start(Pid, MonRef, Tag) ->
    receive
        {Tag, ok} -> sse_link_ready(Pid, MonRef, Tag);
        {Tag, {error, Reason}} ->
            receive {'DOWN', MonRef, process, Pid, _} -> ok end,
            demonitor(MonRef, [flush]), {error, Reason};
        {'DOWN', MonRef, process, Pid, Why} ->
            sse_flush_tag(Tag), {error, reason_binary(Why)}
    after 1000 ->
        exit(Pid, kill),
        %% DOWN orders the child's earlier sends. Flush only after DOWN, never
        %% before it: a delayed ready then cannot remain in a supervisor inbox.
        receive {'DOWN', MonRef, process, Pid, _} -> ok end,
        demonitor(MonRef, [flush]), sse_flush_tag(Tag),
        {error, <<"subscriber_start_timeout">>}
    end.

sse_link_ready(Pid, MonRef, Tag) ->
    %% The ready sender may have died while the caller was descheduled. Trap
    %% only across link + acknowledged handoff, so link(noproc) is a Result,
    %% never a fatal signal to an untrapping caller. Restore its original flag.
    WasTrapping = process_flag(trap_exit, true),
    Result = try
        link(Pid), Pid ! {Tag, linked},
        receive
            {Tag, linked_ack} -> demonitor(MonRef, [flush]), {ok, Pid};
            {'DOWN', MonRef, process, Pid, Why} ->
                unlink(Pid), sse_flush_tag(Tag), {error, reason_binary(Why)};
            {'EXIT', Pid, Why} ->
                receive {'DOWN', MonRef, process, Pid, _} -> ok end,
                demonitor(MonRef, [flush]), sse_flush_tag(Tag),
                {error, reason_binary(Why)}
        after 1000 ->
            unlink(Pid), exit(Pid, kill),
            receive {'DOWN', MonRef, process, Pid, _} -> ok end,
            demonitor(MonRef, [flush]), sse_flush_tag(Tag),
            {error, <<"subscriber_start_timeout">>}
        end
    after process_flag(trap_exit, WasTrapping) end,
    %% Consume only our child's possible trapped exit. Unrelated caller
    %% messages and monitors remain untouched.
    receive {'EXIT', Pid, WhyAfter} -> {error, reason_binary(WhyAfter)}
    after 0 -> Result end.

sse_flush_tag(Tag) -> receive {Tag, _} -> sse_flush_tag(Tag) after 0 -> ok end.

sse_register(false) -> true;
sse_register(true) ->
    case whereis(uos_mcp_zenoh_subscriber) of
        undefined ->
            try register(uos_mcp_zenoh_subscriber, self())
            catch error:badarg -> false end;
        _ -> false
    end.

sse_unregister(true) ->
    case whereis(uos_mcp_zenoh_subscriber) of
        P when P =:= self() -> unregister(uos_mcp_zenoh_subscriber);
        _ -> ok
    end;
sse_unregister(false) -> ok.

sse_lock(0) -> {ok, none};
sse_lock(Port) ->
    gen_tcp:listen(Port, [binary, {active, false}, {ip, {127,0,0,1}},
                          {reuseaddr, true}]).
sse_close_lock(none) -> ok;
sse_close_lock(Socket) -> gen_tcp:close(Socket).

stop_zenoh_sse_subscriber(Pid) when is_pid(Pid) ->
    Ref = monitor(process, Pid),
    unlink(Pid), exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, _} -> true
    after 1000 -> demonitor(Ref, [flush]), false end.

%% Publish one immutable owner/ref pair per registered worker lifetime. Mutable
%% freshness lives in atomics: no persistent-term replacement or literal-area
%% GC is scheduled by network traffic, reconnects, or disconnect cleanup.
sse_meta_init(false, _) -> none;
sse_meta_init(true, Idle) ->
    Atomics = atomics:new(3, [{signed, true}]),
    atomics:put(Atomics, 1, 0),
    atomics:put(Atomics, 2, ?UNOBSERVED_ACTIVITY),
    atomics:put(Atomics, 3, max(1000, Idle * 2)),
    Meta = {self(), Atomics},
    persistent_term:put(uos_mcp_zenoh_subscriber_meta, Meta),
    Meta.

sse_meta(none, _, _) -> ok;
sse_meta({Owner, Atomics}, Connected, Idle) when Owner =:= self() ->
    atomics:put(Atomics, 3, max(1000, Idle * 2)),
    case Connected of
        true ->
            %% Publish the receive timestamp before marking a connection fresh.
            atomics:put(Atomics, 2, erlang:monotonic_time(millisecond)),
            atomics:put(Atomics, 1, 1);
        false -> atomics:put(Atomics, 1, 0)
    end;
sse_meta(_, _, _) -> ok.

sse_observed_meta() ->
    case {whereis(uos_mcp_zenoh_subscriber),
          persistent_term:get(uos_mcp_zenoh_subscriber_meta, undefined)} of
        {Owner, {Owner, Atomics}} when is_pid(Owner) ->
            case is_process_alive(Owner) of
                true -> {ok, Atomics};
                false -> none
            end;
        _ -> none
    end.

zenoh_subscriber_alive() ->
    case sse_observed_meta() of
        {ok, Atomics} ->
            Connected = atomics:get(Atomics, 1),
            Last = atomics:get(Atomics, 2),
            Window = atomics:get(Atomics, 3),
            Connected =:= 1 andalso Last =/= ?UNOBSERVED_ACTIVITY andalso
                erlang:monotonic_time(millisecond) - Last =< Window;
        none -> false
    end.

zenoh_subscriber_state() ->
    case zenoh_subscriber_alive() of
        true -> <<"connected_fresh">>;
        false -> case whereis(uos_mcp_zenoh_subscriber) of
            P when is_pid(P) ->
                case is_process_alive(P) of
                    true -> <<"reconnecting_or_stale">>;
                    false -> <<"stopped">>
                end;
            _ -> <<"stopped">>
        end
    end.

zenoh_subscriber_last_activity_age_ms() ->
    case sse_observed_meta() of
        {ok, Atomics} ->
            case atomics:get(Atomics, 2) of
                ?UNOBSERVED_ACTIVITY -> -1;
                Last -> max(0, erlang:monotonic_time(millisecond) - Last)
            end;
        none -> -1
    end.

sse_reconnect(Host, Port, Handler, Meta, Idle) ->
    case gen_tcp:connect(binary_to_list(Host), Port,
          [binary, {active, false}, {packet, raw}, {recbuf, 16384},
           {keepalive, true}, {send_timeout, 3000}, {send_timeout_close, true}], 3000) of
        {ok, Socket} ->
            try
                ok = gen_tcp:send(Socket, [
                    "GET /indrajaal/mcp/request/** HTTP/1.1\r\nHost: ", Host, ":",
                    integer_to_list(Port), "\r\nAccept: text/event-stream\r\n",
                    "Accept-Encoding: identity\r\nConnection: close\r\n\r\n"]),
                Deadline = erlang:monotonic_time(millisecond) + 3000,
                {Headers, Body} = sse_headers(Socket, <<>>, Deadline),
                Mode = sse_response_mode(Headers),
                sse_meta(Meta, true, Idle),
                sse_body(Socket, Host, Port, Handler, Mode, Body, <<>>, false, Meta, Idle)
            catch _:_ -> ok
            after sse_meta(Meta, false, Idle), gen_tcp:close(Socket) end;
        _ -> sse_meta(Meta, false, Idle)
    end,
    Delay = case Host of <<"127.0.0.1">> -> 200; _ -> 1000 end,
    receive sse_stop -> ok after Delay -> sse_reconnect(Host, Port, Handler, Meta, Idle) end.

sse_headers(Socket, Bytes, Deadline) ->
    case binary:match(Bytes, <<"\r\n\r\n">>) of
        {At, 4} when At =< 16384 ->
            <<Head:At/binary, _:4/binary, Rest/binary>> = Bytes,
            {Head, Rest};
        _ when byte_size(Bytes) > 16384 -> error(header_overflow);
        _ ->
            {ok, More} = gen_tcp:recv(Socket, 0, remaining_ms(Deadline)),
            sse_headers(Socket, <<Bytes/binary, More/binary>>, Deadline)
    end.

remaining_ms(Deadline) ->
    Left = Deadline - erlang:monotonic_time(millisecond),
    case Left > 0 of true -> Left; false -> error(deadline_exceeded) end.

sse_response_mode(Head) ->
    [Status | Lines] = binary:split(Head, <<"\r\n">>, [global]),
    [Version, <<"200">> | _] = binary:split(Status, <<" ">>, [global]),
    true = (Version =:= <<"HTTP/1.1">> orelse Version =:= <<"HTTP/1.0">>),
    Headers = lists:map(fun(Line) ->
        case binary:split(Line, <<":">>) of
            [K, V] -> {string:lowercase(K), string:trim(string:lowercase(V))};
            _ -> error(malformed_header)
        end
    end, Lines),
    [ContentType] = [V || {<<"content-type">>, V} <- Headers],
    [<<"text/event-stream">> | _] = binary:split(ContentType, <<";">>),
    [] = [V || {<<"content-encoding">>, V} <- Headers, V =/= <<"identity">>],
    case [V || {<<"transfer-encoding">>, V} <- Headers] of
        [] -> raw;
        [<<"chunked">>] -> {chunk_size, <<>>};
        _ -> error(unsupported_transfer_encoding)
    end.

sse_body(Socket, Host, Port, Handler, Mode, Bytes, Pending, CR, Meta, Idle) ->
    {NextMode, NextPending, NextCR} =
        sse_transfer(Mode, Bytes, Pending, CR, Host, Port, Handler),
    case gen_tcp:recv(Socket, 0, Idle) of
        {ok, More} ->
            sse_meta(Meta, true, Idle),
            sse_body(Socket, Host, Port, Handler, NextMode, More, NextPending, NextCR, Meta, Idle);
        _ -> ok
    end.

%% Chunk sizes are never used to allocate a chunk: consume at most the bytes
%% already received, retaining only a bounded partial size line or CRLF marker.
sse_transfer(raw, Bytes, Pending, CR, Host, Port, Handler) ->
    {P, C} = sse_events(Bytes, Pending, CR, Host, Port, Handler),
    {raw, P, C};
sse_transfer({chunk_size, Line}, Bytes, Pending, CR, Host, Port, Handler) ->
    Combined = <<Line/binary, Bytes/binary>>,
    case binary:match(Combined, <<"\r\n">>) of
        {At, 2} when At =< 128 ->
            <<SizeLine:At/binary, _:2/binary, Rest/binary>> = Combined,
            [Hex | _] = binary:split(SizeLine, <<";">>),
            true = byte_size(Hex) > 0 andalso byte_size(Hex) =< 16,
            true = lists:all(fun(C) ->
                (C >= $0 andalso C =< $9) orelse (C >= $a andalso C =< $f)
                orelse (C >= $A andalso C =< $F) end, binary_to_list(Hex)),
            Size = binary_to_integer(Hex, 16),
            case Size of 0 -> error(stream_end); _ ->
                sse_transfer({chunk_data, Size}, Rest, Pending, CR, Host, Port, Handler)
            end;
        nomatch when byte_size(Combined) =< 128 ->
            {{chunk_size, Combined}, Pending, CR};
        _ -> error(chunk_header_overflow)
    end;
sse_transfer({chunk_data, Left}, Bytes, Pending, CR, Host, Port, Handler) ->
    N = min(Left, byte_size(Bytes)),
    <<Part:N/binary, Rest/binary>> = Bytes,
    {P, C} = sse_events(Part, Pending, CR, Host, Port, Handler),
    case Left - N of
        0 -> sse_transfer({chunk_crlf, <<>>}, Rest, P, C, Host, Port, Handler);
        Rem -> {{chunk_data, Rem}, P, C}
    end;
sse_transfer({chunk_crlf, Prefix}, Bytes, Pending, CR, Host, Port, Handler) ->
    Combined = <<Prefix/binary, Bytes/binary>>,
    case Combined of
        <<"\r\n", Rest/binary>> ->
            sse_transfer({chunk_size, <<>>}, Rest, Pending, CR, Host, Port, Handler);
        <<>> -> {{chunk_crlf, <<>>}, Pending, CR};
        <<"\r">> -> {{chunk_crlf, <<"\r">>}, Pending, CR};
        _ -> error(malformed_chunk_terminator)
    end.

sse_events(Bytes0, Pending, PreviousCR, Host, Port, Handler) ->
    Bytes = case {PreviousCR, Bytes0} of
        {true, <<"\n", R/binary>>} -> R;
        _ -> Bytes0
    end,
    CR = case byte_size(Bytes0) of
        0 -> PreviousCR;
        _ -> binary:last(Bytes0) =:= $\r
    end,
    Normal = binary:replace(binary:replace(Bytes, <<"\r\n">>, <<"\n">>, [global]),
                            <<"\r">>, <<"\n">>, [global]),
    {sse_complete(<<Pending/binary, Normal/binary>>, Host, Port, Handler), CR}.

sse_complete(Bytes, Host, Port, Handler) ->
    case binary:match(Bytes, <<"\n\n">>) of
        {At, 2} when At =< ?MAX_LINE_BYTES ->
            <<Block:At/binary, _:2/binary, Rest/binary>> = Bytes,
            case unicode:characters_to_binary(Block, utf8, utf8) of
                Valid when is_binary(Valid) ->
                    case Handler(Valid) of
                        {some, {Topic, Response}} -> sse_publish(Host, Port, Topic, Response);
                        none -> ok
                    end;
                _ -> ok
            end,
            sse_complete(Rest, Host, Port, Handler);
        nomatch when byte_size(Bytes) =< ?MAX_LINE_BYTES ->
            %% Copy prevents a subbinary from retaining a previous whole event.
            binary:copy(Bytes);
        _ -> error(sse_buffer_overflow)
    end.

safe_response_topic(Topic) when is_binary(Topic), byte_size(Topic) =< 512 ->
    case binary:split(Topic, <<"/">>, [global]) of
        [<<"indrajaal">>, <<"mcp">>, <<"response">> | Parts] when Parts =/= [] ->
            lists:all(fun safe_response_segment/1, Parts);
        _ -> false
    end;
safe_response_topic(_) -> false.

safe_response_segment(S) when S =/= <<>>, S =/= <<".">>, S =/= <<"..">> ->
    lists:all(fun(C) ->
        (C >= $a andalso C =< $z) orelse (C >= $A andalso C =< $Z)
        orelse (C >= $0 andalso C =< $9) orelse lists:member(C, "_.-")
    end, binary_to_list(S));
safe_response_segment(_) -> false.

sse_publish(Host, Port, Topic, Response)
  when is_binary(Response), byte_size(Response) =< ?MAX_LINE_BYTES ->
    case safe_response_topic(Topic) of
        false -> ok;
        true ->
            Deadline = erlang:monotonic_time(millisecond) + 3000,
            case gen_tcp:connect(binary_to_list(Host), Port,
                  [binary, {active, false}, {packet, raw}, {send_timeout, 3000},
                   {send_timeout_close, true}], remaining_ms(Deadline)) of
                {ok, Socket} ->
                    try
                        ok = inet:setopts(Socket, [{send_timeout, remaining_ms(Deadline)}]),
                        ok = gen_tcp:send(Socket, ["PUT /", Topic, " HTTP/1.1\r\nHost: ",
                            Host, ":", integer_to_list(Port),
                            "\r\nContent-Type: application/json\r\nAccept-Encoding: identity",
                            "\r\nConnection: close\r\nContent-Length: ",
                            integer_to_list(byte_size(Response)), "\r\n\r\n", Response]),
                        {_Head, _} = sse_headers(Socket, <<>>, Deadline),
                        ok
                    catch _:_ -> ok after gen_tcp:close(Socket) end;
                _ -> ok
            end
    end;
sse_publish(_, _, _, _) -> ok.

%% Trusted EUnit fixture only: an ephemeral IPv4 loopback listener. All accepted
%% sockets belong to the monitored fixture process and are closed on termination.
zenoh_sse_loopback_fixture(Valid, Forged, Ping, Start) ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false}, {packet, raw},
                                      {ip, {127,0,0,1}}, {reuseaddr, true}]),
    {ok, {_, Port}} = inet:sockname(Listener),
    Parent = self(),
    {Server, Ref} = spawn_monitor(fun() ->
        try
            {ok, Stream} = gen_tcp:accept(Listener, 2000),
            {Head, <<>>} = sse_headers(Stream, <<>>, test_deadline()),
            true = lists:prefix("GET /indrajaal/mcp/request/** HTTP/1.1", binary_to_list(Head)),
            true = binary:match(Head, <<"Accept: text/event-stream">>) =/= nomatch,
            true = binary:match(Head, <<"Accept-Encoding: identity">>) =/= nomatch,
            ok = gen_tcp:send(Stream, <<"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n">>),
            %% Split both transfer chunk headers/terminators and SSE CRLF pairs.
            test_send_chunk(Stream, <<":keepalive\r\n\r\n">>),
            N = byte_size(Valid) - 3,
            <<A:N/binary, B/binary>> = Valid,
            test_send_chunk(Stream, A), test_send_chunk(Stream, B),
            {Body, PutHead} = test_receive_put(Listener),
            true = binary:match(PutHead, <<"PUT /indrajaal/mcp/response/codex/loop1 HTTP/1.1">>) =/= nomatch,
            test_send_chunk(Stream, Forged),
            {error, timeout} = gen_tcp:accept(Listener, 250),
            %% No delimiter: overflow must close the connection, not retain it.
            Huge = binary:copy(<<"x">>, ?MAX_LINE_BYTES + 1),
            ok = gen_tcp:send(Stream, [integer_to_list(byte_size(Huge), 16), "\r\n", Huge, "\r\n"]),
            {error, closed} = gen_tcp:recv(Stream, 0, 2000),
            gen_tcp:close(Stream),
            {ok, Again} = gen_tcp:accept(Listener, 2000),
            {_AgainHead, <<>>} = sse_headers(Again, <<>>, test_deadline()),
            %% Reconnected close-delimited stream also supports bare CR.
            ok = gen_tcp:send(Again, <<"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n">>),
            ok = gen_tcp:send(Again, binary:replace(Ping, <<"\r\n">>, <<"\r">>, [global])),
            {PingBody, PingHead} = test_receive_put(Listener),
            true = binary:match(PingHead, <<"PUT /indrajaal/mcp/response/codex/loop2 HTTP/1.1">>) =/= nomatch,
            gen_tcp:close(Again),
            %% EOF reconnect and non-200 status are rejected and retried.
            {ok, Third} = gen_tcp:accept(Listener, 2000),
            {_, <<>>} = sse_headers(Third, <<>>, test_deadline()),
            ok = gen_tcp:send(Third, <<"HTTP/1.1 302 Found\r\nLocation: http://evil.example/\r\nContent-Type: text/event-stream\r\n\r\n">>),
            {error, closed} = gen_tcp:recv(Third, 0, 2000),
            gen_tcp:close(Third),
            {ok, Fourth} = gen_tcp:accept(Listener, 2000),
            {_, <<>>} = sse_headers(Fourth, <<>>, test_deadline()),
            gen_tcp:close(Fourth),
            Parent ! {self(), fixture_result, {ok, {Body, PingBody}}}
        catch Class:Reason:Stack ->
            Parent ! {self(), fixture_result, {error,
                unicode:characters_to_binary(io_lib:format("~p:~p at ~p", [Class, Reason, Stack]))}}
        end
    end),
    try
        {ok, Subscriber} = Start(Port),
        try
            receive
                {Server, fixture_result, Result} -> Result;
                {'DOWN', Ref, process, Server, Why} -> {error, reason_binary(Why)}
            after 8000 -> {error, <<"loopback_fixture_timeout">>}
            end
        after true = stop_zenoh_sse_subscriber(Subscriber) end
    after
        exit(Server, kill),
        receive {'DOWN', Ref, process, Server, _} -> ok after 1000 -> ok end,
        gen_tcp:close(Listener),
        demonitor(Ref, [flush])
    end.

test_deadline() -> erlang:monotonic_time(millisecond) + 2000.

test_send_chunk(Socket, Bytes) ->
    Wire = iolist_to_binary([integer_to_list(byte_size(Bytes), 16), "\r\n", Bytes, "\r\n"]),
    <<First:1/binary, Rest/binary>> = Wire,
    ok = gen_tcp:send(Socket, First),
    receive after 2 -> ok end,
    %% End the first write at a CR when possible to test split CRLF.
    N = max(1, byte_size(Rest) - 1),
    <<Middle:N/binary, Last/binary>> = Rest,
    ok = gen_tcp:send(Socket, Middle),
    receive after 2 -> ok end,
    ok = gen_tcp:send(Socket, Last).

test_receive_put(Listener) ->
    {ok, Socket} = gen_tcp:accept(Listener, 2000),
    try
        Deadline = test_deadline(),
        {Head, Rest} = sse_headers(Socket, <<>>, Deadline),
        [LengthLine] = [L || L <- binary:split(Head, <<"\r\n">>, [global]),
                            binary:match(L, <<"Content-Length: ">>) =:= {0,16}],
        <<"Content-Length: ", Length/binary>> = LengthLine,
        Size = binary_to_integer(Length),
        true = Size =< ?MAX_LINE_BYTES,
        Body = test_read_body(Socket, Rest, Size, Deadline),
        ok = gen_tcp:send(Socket, <<"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n">>),
        {Body, Head}
    after gen_tcp:close(Socket) end.

test_read_body(_, Bytes, Size, _) when byte_size(Bytes) =:= Size -> Bytes;
test_read_body(Socket, Bytes, Size, Deadline) when byte_size(Bytes) < Size ->
    {ok, More} = gen_tcp:recv(Socket, Size - byte_size(Bytes), remaining_ms(Deadline)),
    test_read_body(Socket, <<Bytes/binary, More/binary>>, Size, Deadline).

%% Stdio is an entire ephemeral VM role. Retain this exclusion even when its
%% caller omitted CLIENT_NAME and a later stdio request invokes ensure_started.
mark_stdio_gateway() -> persistent_term:put(uos_mcp_stdio_only, true), nil.
stdio_gateway() -> persistent_term:get(uos_mcp_stdio_only, false).

%% Registered branch fixtures use ephemeral loopback sockets exclusively.
zenoh_sse_registered_health_fixture(Start) ->
    test_with_router(fun(Port, Router) ->
        {ok, Pid} = Start(Port, 0),
        try
            test_wait(fun zenoh_subscriber_alive/0, 1500),
            <<"connected_fresh">> = zenoh_subscriber_state(),
            Age = zenoh_subscriber_last_activity_age_ms(),
            true = Age >= 0 andalso Age < 1000,
            test_router_mode(Router, stalled),
            test_wait(fun() -> not zenoh_subscriber_alive() end, 1000),
            <<"reconnecting_or_stale">> = zenoh_subscriber_state(),
            true = is_process_alive(Pid),
            test_router_mode(Router, running),
            test_wait(fun zenoh_subscriber_alive/0, 1500),
            <<"connected_fresh">> = zenoh_subscriber_state(),
            {ok, nil}
        after true = stop_zenoh_sse_subscriber(Pid) end
    end).

zenoh_sse_registered_isolation_fixture(StartSupervisor, Start, Boot) ->
    test_with_router(fun(Port, _Router) ->
        {ok, Reserve} = sse_lock(test_unused_port()),
        {ok, {_, LockPort}} = inet:sockname(Reserve),
        gen_tcp:close(Reserve),
        {ok, Sup} = StartSupervisor(Port, LockPort),
        try
            true = register_or_keep_zenoh_supervisor(Sup),
            true = register_or_keep_zenoh_supervisor(Sup),
            test_wait(fun zenoh_subscriber_alive/0, 1500),
            First = whereis(uos_mcp_zenoh_subscriber),
            {error, eaddrinuse} = sse_lock(LockPort),
            %% Name collision and mutex-only collision from untrapping callers.
            test_untrapping_collision(fun() -> Start(Port, true, 0) end),
            test_untrapping_collision(fun() -> Start(Port, false, LockPort) end),
            %% A separate BEAM has its own name registry. Only the kernel mutex
            %% can exclude this process; success here would be duplicate effects.
            test_cross_beam_collision(Port, LockPort),
            test_with_env([
                {"UOS_MCP_ZENOH_SUBSCRIBER", "1"},
                {"UOS_MCP_ZENOH_SHARED_SECRET", "registered-fixture-secret"},
                {"UOS_MCP_CLIENT_NAME", false}
            ], fun() -> true = Boot() end),
            Owner = persistent_term:get(uos_mcp_runtime_gateway_subject),
            exit(First, kill),
            test_wait(fun() ->
                P = whereis(uos_mcp_zenoh_subscriber),
                is_pid(P) andalso P =/= First andalso zenoh_subscriber_alive()
            end, 1500),
            {error, eaddrinuse} = sse_lock(LockPort),
            Owner = persistent_term:get(uos_mcp_runtime_gateway_subject),
            %% Exhaust the independent restart budget. Its death cannot exhaust
            %% the GatewayState supervisor's budget or replace the owner.
            test_crash_subscriber(5),
            test_wait(fun() -> not is_process_alive(Sup) end, 1500),
            test_wait(fun() -> whereis(uos_mcp_zenoh_subscriber) =:= undefined end, 1000),
            Owner = persistent_term:get(uos_mcp_runtime_gateway_subject),
            test_with_env([{"UOS_MCP_ZENOH_SUBSCRIBER", "0"}], fun() -> true = Boot() end),
            {ok, Available} = sse_lock(LockPort),
            gen_tcp:close(Available),
            {ok, nil}
        after
            test_kill_wait(Sup),
            case whereis(uos_mcp_zenoh_subscriber) of
                P when is_pid(P) -> stop_zenoh_sse_subscriber(P);
                _ -> ok
            end
        end
    end).

zenoh_sse_stdio_guard_fixture(Enabled, StdioMain) ->
    Before = persistent_term:get(uos_mcp_stdio_only, false),
    try
        test_with_env([
            {"UOS_MCP_ZENOH_SUBSCRIBER", "1"},
            {"UOS_MCP_ZENOH_SHARED_SECRET", "stdio-fixture-secret"},
            {"UOS_MCP_CLIENT_NAME", "codex-stdio-test"}
        ], fun() -> false = Enabled() end),
        test_with_env([
            {"UOS_MCP_ZENOH_SUBSCRIBER", "1"},
            {"UOS_MCP_ZENOH_SHARED_SECRET", "stdio-fixture-secret"},
            {"UOS_MCP_CLIENT_NAME", false}
        ], fun() ->
            IO = spawn(fun test_eof_io/0),
            OldLeader = group_leader(),
            try
                true = group_leader(IO, self()),
                StdioMain(),
                false = Enabled(),
                undefined = whereis(uos_mcp_zenoh_subscriber),
                undefined = whereis(uos_mcp_zenoh_sup),
                {ok, nil}
            after group_leader(OldLeader, self()), test_kill_wait(IO) end
        end)
    after persistent_term:put(uos_mcp_stdio_only, Before) end.

test_eof_io() ->
    receive
        {io_request, From, Tag, Request} ->
            Reply = case Request of
                {setopts, _} -> ok;
                {getopts} -> [{encoding, unicode}];
                {get_line, _, _} -> eof;
                {get_line, _} -> eof;
                _ -> ok
            end,
            From ! {io_reply, Tag, Reply}, test_eof_io()
    end.

test_with_env(Pairs, Fun) ->
    Old = [{K, os:getenv(K)} || {K, _} <- Pairs],
    Set = fun({K, false}) -> os:unsetenv(K); ({K, V}) -> os:putenv(K, V) end,
    lists:foreach(Set, Pairs),
    try Fun() after lists:foreach(Set, Old) end.

test_untrapping_collision(Fun) ->
    Parent = self(), Tag = make_ref(),
    {Pid, Ref} = spawn_monitor(fun() ->
        false = process_flag(trap_exit, false),
        Result = Fun(),
        receive after 10 -> ok end,
        {messages, []} = process_info(self(), messages),
        Parent ! {Tag, Result}
    end),
    receive {Tag, {error, <<"subscriber_already_active">>}} -> ok;
            {'DOWN', Ref, process, Pid, Why} -> error({caller_died, Why})
    after 2000 -> exit(Pid, kill), error(collision_timeout) end,
    receive {'DOWN', Ref, process, Pid, normal} -> ok after 1000 -> error(caller_not_clean) end.

test_cross_beam_collision(Port, LockPort) ->
    Expr = lists:flatten(io_lib:format(
        "{error,<<\"subscriber_already_active\">>}=mcp_stdio_ffi:start_zenoh_sse_subscriber(<<\"127.0.0.1\">>,~p,<<\"cross-beam-fixture\">>,true,~p,150,fun(_)->none end),"
        "true='cepaf_gleam@mcp@runtime_gateway':ensure_started_with_subscriber_for_test(fun()->case 'cepaf_gleam@mcp@runtime_gateway':start_zenoh_supervisor_with_options_for_test(<<\"127.0.0.1\">>,~p,<<\"cross-beam-fixture\">>,true,~p,150) of {error,_}->false;_->exit(unexpected_subscriber) end end),"
        "true='cepaf_gleam@mcp@runtime_gateway':is_running(),io:put_chars(\"MUTEX_PASS\"),halt(0).",
        [Port, LockPort, Port, LockPort])),
    Erl = filename:join([code:root_dir(), "bin", "erl"]),
    Paths = lists:append([["-pa", P] || P <- code:get_path(), filelib:is_dir(P)]),
    Child = open_port({spawn_executable, Erl},
        [binary, use_stdio, exit_status, stderr_to_stdout,
         {env, [{"ERL_CRASH_DUMP_SECONDS", "0"}]},
         {args, ["+S", "1:1", "+A", "1", "-noshell"] ++ Paths ++ ["-eval", Expr]}]),
    try test_collect_beam(Child, <<>>, test_deadline() + 3000)
    after try port_close(Child) catch _:_ -> ok end end.

test_collect_beam(Port, Bytes, Deadline) ->
    receive
        {Port, {data, More}} when byte_size(Bytes) + byte_size(More) =< 4096 ->
            test_collect_beam(Port, <<Bytes/binary, More/binary>>, Deadline);
        {Port, {exit_status, 0}} -> true = binary:match(Bytes, <<"MUTEX_PASS">>) =/= nomatch;
        {Port, {exit_status, Status}} -> error({cross_beam_failed, Status, Bytes})
    after remaining_ms(Deadline) -> error(cross_beam_timeout) end.

test_crash_subscriber(0) -> ok;
test_crash_subscriber(N) ->
    test_wait(fun() -> is_pid(whereis(uos_mcp_zenoh_subscriber)) end, 1000),
    Pid = whereis(uos_mcp_zenoh_subscriber),
    test_kill_wait(Pid),
    test_crash_subscriber(N - 1).

test_unused_port() ->
    {ok, S} = gen_tcp:listen(0, [{ip, {127,0,0,1}}, {active, false}]),
    {ok, {_, Port}} = inet:sockname(S), gen_tcp:close(S), Port.

test_with_router(Fun) ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false}, {packet, raw},
                                      {ip, {127,0,0,1}}, {reuseaddr, true}]),
    {ok, {_, Port}} = inet:sockname(Listener),
    Router = spawn(fun() -> test_router(Listener, running, []) end),
    try Fun(Port, Router)
    catch Class:Reason:Stack ->
        {error, unicode:characters_to_binary(io_lib:format("~p:~p at ~p", [Class,Reason,Stack]))}
    after test_kill_wait(Router), gen_tcp:close(Listener) end.

test_router_mode(Router, Mode) ->
    Ref = make_ref(), Router ! {mode, Mode, self(), Ref},
    receive {Ref, ok} -> ok after 500 -> error(router_control_timeout) end.

test_router(Listener, Mode0, Sockets0) ->
    Mode = receive {mode, Next, Parent, Ref} -> Parent ! {Ref, ok}, Next
           after 0 -> Mode0 end,
    Sockets1 = case gen_tcp:accept(Listener, 20) of
        {ok, S} ->
            {_, _} = sse_headers(S, <<>>, test_deadline()),
            [{S, false} | Sockets0];
        {error, timeout} -> Sockets0;
        {error, closed} -> exit(normal)
    end,
    Sockets = lists:filtermap(fun({S, Sent}) ->
        case Mode of
            stalled -> {true, {S, Sent}};
            Active when Active =:= running; Active =:= events ->
                Header = case Sent of
                    true -> <<>>;
                    false -> <<"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n">>
                end,
                Data = case Active of
                    events -> <<"event: sample\ndata: {}\n\n">>;
                    running -> <<":keepalive\n\n">>
                end,
                case gen_tcp:send(S, [Header, Data]) of
                    ok -> {true, {S, true}};
                    _ -> gen_tcp:close(S), false
                end
        end
    end, Sockets1),
    test_router(Listener, Mode, Sockets).

test_wait(Fun, Ms) -> test_wait_until(Fun, erlang:monotonic_time(millisecond) + Ms).
test_wait_until(Fun, Deadline) ->
    case Fun() of
        true -> ok;
        false ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true -> receive after 5 -> ok end, test_wait_until(Fun, Deadline);
                false -> error(condition_timeout)
            end
    end.

test_kill_wait(Pid) ->
    Ref = monitor(process, Pid), unlink(Pid), exit(Pid, kill),
    receive {'DOWN', Ref, process, Pid, _} -> ok after 1000 -> error(cleanup_timeout) end.

zenoh_test_environment(Fun) ->
    test_with_env([{"UOS_MCP_ZENOH_SHARED_SECRET", "raw-topic-test-secret"}], Fun).

%% OTP start_link may emit a linked shutdown in addition to its Error result.
%% Contain both in an expendable trapping launcher; the gateway caller is never
%% linked to either the launcher or the independent SSE supervisor.
isolate_zenoh_supervisor_start(Start) ->
    Parent = self(), Tag = make_ref(),
    {Pid, Ref} = spawn_monitor(fun() ->
        process_flag(trap_exit, true),
        Result = try Start() catch _:_ -> {error, <<"zenoh_supervisor_start_failed">>} end,
        Parent ! {Tag, Result}
    end),
    receive
        {Tag, Result} ->
            receive {'DOWN', Ref, process, Pid, _} -> ok end,
            demonitor(Ref, [flush]), Result;
        {'DOWN', Ref, process, Pid, _} ->
            receive {Tag, _} -> ok after 0 -> ok end,
            {error, <<"zenoh_supervisor_start_failed">>}
    after 3500 ->
        exit(Pid, kill),
        receive {'DOWN', Ref, process, Pid, _} -> ok end,
        demonitor(Ref, [flush]),
        receive
            {Tag, {ok, Sup}} ->
                try gen_server:stop(Sup, shutdown, 1000) catch _:_ -> ok end;
            {Tag, _} -> ok
        after 0 -> ok end,
        {error, <<"zenoh_supervisor_start_timeout">>}
    end.

zenoh_sse_handshake_fixture() ->
    Parent = self(), Ref = make_ref(),
    {Caller, Mon} = spawn_monitor(fun() ->
        false = process_flag(trap_exit, false),
        lists:foreach(fun(Mode) ->
            Tag = make_ref(), Self = self(),
            {Pid, ChildMon} = spawn_monitor(fun() ->
                case Mode of
                    ready_then_dead -> Self ! {Tag, ok}, exit(init_failed);
                    crash -> Self ! {Tag, stale}, exit(init_failed);
                    timeout -> receive after 1500 -> Self ! {Tag, ok} end
                end
            end),
            case Mode of ready_then_dead -> receive after 20 -> ok end; _ -> ok end,
            {error, _} = sse_await_start(Pid, ChildMon, Tag),
            false = is_process_alive(Pid),
            receive after 5 -> ok end,
            {messages, []} = process_info(self(), messages)
        end, [ready_then_dead, crash, timeout]),
        Parent ! {Ref, ok}
    end),
    receive
        {Ref, ok} ->
            receive {'DOWN', Mon, process, Caller, normal} -> {ok, nil} end;
        {'DOWN', Mon, process, Caller, Why} -> {error, reason_binary(Why)}
    after 3000 -> test_kill_wait(Caller), {error, <<"handshake_fixture_timeout">>}
    end.

%% Exercise the actual registered network reader while tracing only its calls
%% in an isolated OTP trace session. Unrelated tracing sessions are untouched.
zenoh_sse_atomics_fixture(Start) ->
    test_with_router(fun(Port, Router) ->
        {ok, Pid} = Start(Port),
        Session = trace:session_create(s03_zenoh_atomics, self(), []),
        try
            test_wait(fun zenoh_subscriber_alive/0, 1500),
            Meta = {Pid, Atomics} = persistent_term:get(uos_mcp_zenoh_subscriber_meta),
            1 = atomics:get(Atomics, 1),
            1000 = atomics:get(Atomics, 3),
            1 = trace:function(Session, {persistent_term, put, 2}, true, []),
            1 = trace:function(Session, {atomics, put, 3}, true, []),
            1 = trace:process(Session, Pid, true, [call]),
            test_router_mode(Router, events),
            lists:foreach(fun(_) ->
                Last = atomics:get(Atomics, 2),
                test_wait(fun() -> atomics:get(Atomics, 2) > Last end, 500),
                Meta = persistent_term:get(uos_mcp_zenoh_subscriber_meta),
                Age = zenoh_subscriber_last_activity_age_ms(),
                true = Age >= 0 andalso Age < 1000
            end, lists:seq(1, 8)),
            %% Reconnect/disconnect must retain the same publication too.
            test_router_mode(Router, stalled),
            test_wait(fun() -> not zenoh_subscriber_alive() end, 1000),
            0 = atomics:get(Atomics, 1),
            Meta = persistent_term:get(uos_mcp_zenoh_subscriber_meta),
            test_router_mode(Router, running),
            test_wait(fun zenoh_subscriber_alive/0, 1500),
            Meta = persistent_term:get(uos_mcp_zenoh_subscriber_meta),
            %% A previous worker can finish cleanup only through its own ref,
            %% even while a replacement owns the globally published pair.
            OldAtomics = atomics:new(3, [{signed, true}]),
            sse_meta({self(), OldAtomics}, true, 150),
            sse_meta({self(), OldAtomics}, false, 150),
            0 = atomics:get(OldAtomics, 1),
            1 = atomics:get(Atomics, 1),
            Meta = persistent_term:get(uos_mcp_zenoh_subscriber_meta),
            1 = trace:process(Session, Pid, false, [call]),
            Fence = trace:delivered(Session, Pid),
            {0, TimestampWrites} = test_meta_trace(Pid, Atomics, Fence, 0, 0),
            true = TimestampWrites >= 8,
            {ok, nil}
        after
            trace:session_destroy(Session),
            true = stop_zenoh_sse_subscriber(Pid)
        end
    end).

test_meta_trace(Pid, Atomics, Fence, Publications, TimestampWrites) ->
    receive
        {trace, Pid, call, {persistent_term, put, _}} ->
            test_meta_trace(Pid, Atomics, Fence, Publications + 1, TimestampWrites);
        {trace, Pid, call, {atomics, put, [Atomics, 2, _]}} ->
            test_meta_trace(Pid, Atomics, Fence, Publications, TimestampWrites + 1);
        {trace, Pid, call, {atomics, put, _}} ->
            test_meta_trace(Pid, Atomics, Fence, Publications, TimestampWrites);
        {trace_delivered, Pid, Fence} -> {Publications, TimestampWrites}
    after 1000 -> error(atomics_trace_timeout) end.
