%% PRIVATE CANDIDATE, iteration 4. Module name is telegram_http_ffi so root's
%% existing Gleam tests exercise it unchanged via a private ebin that precedes
%% the app ebins on the code path. NO shared file is edited.
%%
%% Repairs over candidate 91aec85b (all found by independent review):
%%   R1 A NORMAL connection DOWN no longer preempts an already-queued worker
%%      result. Connection: close legitimately exits normally once the complete
%%      body has been delivered, so conn DOWN is NOT terminal on its own.
%%   R2 Every error is a BINARY. The Gleam contract is
%%      Result(#(Int, List(..), BitArray), String); a tuple reason crashes the
%%      callback with badarg. A fixed vocabulary is used and nothing else.
%%   R3 Cleanup is verified BEFORE the result is published. If reaping cannot be
%%      confirmed the call fails closed with <<"cleanup_unknown">> rather than
%%      returning a success whose invariant was never established.
%%   R4 Reap confirmation is a value, not a silent ok on timeout.
%%   R5 The handoff wait is bounded by the REMAINING deadline, not a flat 1000 ms.
%%   R6 Only http and https are accepted; any other scheme is refused.
%%   R7 No raw term, exception or URL is ever emitted in an error.
%%
%% Iteration 3 closes the ownership protocol holes found in daa518:
%%   R8 The caller ACKs the handoff BEFORE any network work begins. The worker
%%      is spawned but parked, waiting for an explicit begin, and it monitors
%%      the guardian so it never starts work for a dead guardian.
%%   R9 The handoff carries the EXACT conn pid AND the EXACT worker pid, so the
%%      caller can reap both after guardian death.
%%  R10 On any caller-side give-up the caller drains ONLY its own tagged
%%      messages after a confirmed guardian DOWN, and reaps a conn/worker that
%%      arrived in a late handoff. Nothing is left queued and unreaped.
%%  R11 A start_conn failure is returned as a BINARY and is consumed by the
%%      handoff wait, which previously only matched handoff or DOWN and so
%%      leaked that message.
%%  R12 ALPN is explicitly constrained to HTTP/1.1 via {protocols,[http1]}.
%%      hackney defaults to [http2, http1], so without this the transport may
%%      negotiate h2. This restricts the ALPN offer only; it does NOT weaken
%%      certificate verification or any other TLS property. Verified in pinned
%%      source: hackney_ssl:alpn_opts/1 (hackney_ssl.erl:287-300) maps
%%      {protocols,[http1]} to [{alpn_advertised_protocols,[<<"http/1.1">>]}]
%%      via proto_to_alpn/1 (line 318), and hackney_conn.erl:2276 applies it on
%%      the SSL connect path.
%%
%% Iteration 4:
%%  R13 await_handoff's guardian-DOWN branch no longer discards an unconfirmed
%%      drain: an unconfirmed reap now yields <<"cleanup_unknown">>.
%%  R14 No I/O may start at or after the absolute deadline. The guardian checks
%%      the deadline in the ACK branch, and the worker re-checks before its
%%      first call, so a queued ACK arriving at the deadline cannot use the
%%      max(1, ...) floor to extend the request.
%%  R15 A missing ACK publishes a binary timeout instead of letting the caller
%%      observe only a guardian DOWN.
-module(telegram_http_ffi).

-export([request/6, extract_telegram_updates/1, ensure_started/1, validate_config/2]).
%% Exported ONLY for the private deterministic delayed-ACK test, and ONLY in
%% a -DTEST build. The production-shaped build does not export it, so the
%% adoption surface is exactly request/6 plus extract_telegram_updates/1.
-ifdef(TEST).
-export([guardian/3]).
-endif.

-define(MIN_TIMEOUT_MS, 1).
-define(MAX_TIMEOUT_MS, 60000).
-define(MIN_MAX_BYTES, 1).
-define(MAX_MAX_BYTES, 10485760).
-define(REAP_BUDGET_MS, 250).
-define(CONN_DOWN_GRACE_MS, 250).

%% ------------------------------------------------------------------ bootstrap
ensure_started(BudgetMs) ->
    {P,R} = spawn_monitor(fun() -> exit({started, application:ensure_all_started(hackney)}) end),
    receive
        {'DOWN',R,process,P,{started,{ok,_}}} -> ok;
        {'DOWN',R,process,P,_} -> {error, <<"bootstrap_failed">>}
    after BudgetMs ->
        exit(P,kill),
        receive {'DOWN',R,process,P,_} -> ok after ?REAP_BUDGET_MS -> ok end,
        {error, <<"bootstrap_timeout">>}
    end.

%% ------------------------------------------------------------------ validation
validate_config(TimeoutMs, MaxBytes) ->
    case is_integer(TimeoutMs) andalso TimeoutMs >= ?MIN_TIMEOUT_MS
         andalso TimeoutMs =< ?MAX_TIMEOUT_MS of
        false -> {error, <<"invalid_timeout_ms_out_of_policy">>};
        true ->
            case is_integer(MaxBytes) andalso MaxBytes >= ?MIN_MAX_BYTES
                 andalso MaxBytes =< ?MAX_MAX_BYTES of
                false -> {error, <<"invalid_max_bytes_out_of_policy">>};
                true  -> ok
            end
    end.

%% R6: an unsupported scheme is refused, never silently treated as TCP.
parse_url(Url) when is_binary(Url) -> parse_url(binary_to_list(Url));
parse_url(Url) when is_list(Url) ->
    case uri_string:parse(Url) of
        #{scheme := Scheme, host := Host} = M ->
            case scheme_transport(Scheme) of
                {error,E} -> {error,E};
                {ok,Transport,DefPort} ->
                    Port = maps:get(port, M, DefPort),
                    P0 = maps:get(path, M, "/"),
                    Path = case P0 of "" -> "/"; _ -> P0 end,
                    Full = case maps:get(query, M, undefined) of
                        undefined -> Path;
                        Q -> Path ++ "?" ++ to_list(Q)
                    end,
                    HostL = to_list(Host),
                    case HostL of
                        "" -> {error, <<"invalid_url">>};
                        %% hackney_tcp:connect/4 function_clauses on a BINARY
                        %% host, so a charlist is required here.
                        _ -> {ok, HostL, Port, Transport, list_to_binary(Full)}
                    end
            end;
        _ -> {error, <<"invalid_url">>}
    end;
parse_url(_) -> {error, <<"invalid_url">>}.

scheme_transport(S) ->
    case to_list(S) of
        "http"  -> {ok, hackney_tcp, 80};
        "https" -> {ok, hackney_ssl, 443};
        _ -> {error, <<"unsupported_url_scheme">>}
    end.

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A).

%% ------------------------------------------------------------------ public API
request(Method, Url, Headers, Body, TimeoutMs, MaxBytes) ->
    case validate_config(TimeoutMs, MaxBytes) of
        {error,E} -> {error,E};
        ok ->
            case parse_url(Url) of
                {error,E} -> {error,E};
                {ok,Host,Port,Transport,Path} ->
                    case whereis(hackney_conn_sup) of
                        undefined -> {error, <<"hackney_not_started">>};
                        _ -> run(Method,Host,Port,Transport,Path,Headers,Body,TimeoutMs,MaxBytes)
                    end
            end
    end.

run(Method,Host,Port,Transport,Path,Headers,Body,TimeoutMs,MaxBytes) ->
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    ConnOpts = #{host=>Host, port=>Port, transport=>Transport,
                 connect_timeout=>TimeoutMs, recv_timeout=>TimeoutMs,
                 %% R12 explicit HTTP/1.1; TLS verification untouched.
                 connect_options=>[{protocols,[http1]}], ssl_options=>[]},
    Spec = #{method=>norm_method(Method), path=>Path, headers=>Headers,
             body=>Body, max_bytes=>MaxBytes, deadline=>Deadline},
    Caller = self(),
    {G,GRef} = spawn_monitor(fun() -> guardian(Caller,ConnOpts,Spec) end),
    await_handoff(G,GRef,Deadline).

norm_method(M) when is_atom(M) -> list_to_binary(string:uppercase(atom_to_list(M)));
norm_method(M) when is_binary(M) -> M;
norm_method(M) when is_list(M) -> list_to_binary(M).

%% R5 bounded by the remaining deadline. R8 the caller ACKs before any network
%% work. R11 a startup error is consumed here instead of being left queued.
await_handoff(G,GRef,Deadline) ->
    Wait = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {handoff,G,Conn,W} ->
            G ! {ack,self()},
            await_result(G,GRef,Conn,W,Deadline);
        {http_result,G,Result} ->
            demonitor(GRef,[flush]),
            _ = drain_tagged(G),
            Result;
        {'DOWN',GRef,process,G,_} ->
            %% R13 an unconfirmed reap must not be reported as a clean failure.
            case drain_tagged(G) of
                {reaped,unconfirmed} -> {error, <<"cleanup_unknown">>};
                {reaped,confirmed} -> {error, <<"guardian_failed">>};
                none -> {error, <<"guardian_failed">>}
            end
    after Wait ->
        give_up(G,GRef,<<"timeout">>)
    end.

%% R10 kill, confirm DOWN, then drain ONLY our own tagged messages and reap
%% anything a late handoff revealed. No unrelated message is ever consumed.
give_up(G,GRef,Reason) ->
    exit(G,kill),
    Confirmed = receive {'DOWN',GRef,process,G,_} -> confirmed
                after ?REAP_BUDGET_MS -> demonitor(GRef,[flush]), unconfirmed end,
    Drained = drain_tagged(G),
    case {Confirmed,Drained} of
        {confirmed,{reaped,confirmed}} -> {error,Reason};
        {confirmed,none} -> {error,Reason};
        _ -> {error, <<"cleanup_unknown">>}
    end.

%% Consumes only {handoff,G,_,_} and {http_result,G,_}. Reaps a conn/worker
%% learned from a late handoff. Returns none | {reaped, confirmed|unconfirmed}.
drain_tagged(G) -> drain_tagged(G, none).
drain_tagged(G, Acc) ->
    receive
        {handoff,G,Conn,W} ->
            A = reap(W), B = reap(Conn),
            R = case {A,B} of {confirmed,confirmed} -> confirmed; _ -> unconfirmed end,
            drain_tagged(G, merge_drain(Acc,{reaped,R}));
        {http_result,G,_} ->
            drain_tagged(G, Acc)
    after 0 -> Acc
    end.

merge_drain(none,X) -> X;
merge_drain({reaped,confirmed},{reaped,confirmed}) -> {reaped,confirmed};
merge_drain(_,_) -> {reaped,unconfirmed}.

await_result(G,GRef,Conn,W,Deadline) ->
    Wait = max(0, Deadline - erlang:monotonic_time(millisecond)) + ?REAP_BUDGET_MS*2,
    receive
        {http_result,G,Result} ->
            demonitor(GRef,[flush]), _ = drain_tagged(G), Result;
        {'DOWN',GRef,process,G,_} ->
            %% R9 the caller holds BOTH pids and reaps both.
            A = reap(W), B = reap(Conn), _ = drain_tagged(G),
            case {A,B} of
                {confirmed,confirmed} -> {error, <<"guardian_failed">>};
                _ -> {error, <<"cleanup_unknown">>}
            end
    after Wait ->
        exit(G,kill),
        Confirmed = receive {'DOWN',GRef,process,G,_} -> confirmed
                    after ?REAP_BUDGET_MS -> demonitor(GRef,[flush]), unconfirmed end,
        A2 = reap(W), B2 = reap(Conn), _ = drain_tagged(G),
        case {Confirmed,A2,B2} of
            {confirmed,confirmed,confirmed} -> {error, <<"timeout">>};
            _ -> {error, <<"cleanup_unknown">>}
        end
    end.

%% R4: returns confirmed | unconfirmed. Never a silent ok.
reap(undefined) -> confirmed;
reap(Pid) when is_pid(Pid) ->
    R = monitor(process,Pid),
    exit(Pid,kill),
    receive {'DOWN',R,process,Pid,_} -> confirmed
    after ?REAP_BUDGET_MS -> demonitor(R,[flush]), unconfirmed end.

%% ------------------------------------------------------------------ guardian
guardian(Caller,ConnOpts,Spec) ->
    case hackney_conn_sup:start_conn(ConnOpts#{owner=>self()}) of
        {error,_} ->
            %% R11 binary reason, and await_handoff consumes this message.
            Caller ! {http_result,self(),{error,<<"start_conn_failed">>}},
            exit(normal);
        {ok,Conn} ->
            CRef = monitor(process,Conn),
            CallerRef = monitor(process,Caller),
            G = self(),
            %% R8 worker is spawned PARKED: it performs no network work until
            %% it receives begin, which is sent only after the caller ACKs.
            {W,WRef} = spawn_monitor(fun() -> worker_parked(G,Conn,Spec) end),
            %% R9 handoff carries both exact pids.
            Caller ! {handoff,G,Conn,W},
            Deadline = maps:get(deadline,Spec),
            AckWait = max(0, Deadline - erlang:monotonic_time(millisecond)),
            receive
                {ack,Caller} ->
                    %% R14 a queued ACK that arrives at or after the deadline
                    %% must NOT start I/O.
                    case erlang:monotonic_time(millisecond) < Deadline of
                        true ->
                            W ! {begin_now,G},
                            loop(Caller,Conn,CRef,CallerRef,W,WRef,Deadline,false);
                        false ->
                            finish(Caller,{error,<<"timeout">>},Conn,CRef,W,WRef)
                    end;
                {'DOWN',CallerRef,process,Caller,_} ->
                    cleanup(Conn,CRef,W,WRef), exit(normal)
            after AckWait ->
                %% R15 no ACK within the deadline: no network work was ever
                %% started, and the caller still receives a binary result.
                finish(Caller,{error,<<"timeout">>},Conn,CRef,W,WRef)
            end
    end.

%% ConnDown carries R1: a normal conn exit is recorded, not published.
loop(Caller,Conn,CRef,CallerRef,W,WRef,Deadline,ConnDown) ->
    Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
    Wait = case ConnDown of
        false -> Remaining;
        true  -> min(Remaining, ?CONN_DOWN_GRACE_MS)
    end,
    receive
        {worker_result,W,Result} ->
            finish(Caller,Result,Conn,CRef,W,WRef);
        {'DOWN',WRef,process,W,normal} ->
            %% Worker exited without a result message: nothing to publish.
            finish(Caller,{error,<<"worker_failed">>},Conn,CRef,W,WRef);
        {'DOWN',WRef,process,W,_} ->
            finish(Caller,{error,<<"worker_failed">>},Conn,CRef,W,WRef);
        {'DOWN',CallerRef,process,Caller,_} ->
            cleanup(Conn,CRef,W,WRef),
            exit(normal);
        {'DOWN',CRef,process,Conn,_} ->
            %% R1: do NOT conclude. The complete body may already be queued at
            %% the worker, which will answer within the grace below.
            loop(Caller,Conn,undefined,CallerRef,W,WRef,Deadline,true)
    after Wait ->
        case ConnDown of
            true  -> finish(Caller,{error,<<"connection_closed">>},Conn,CRef,W,WRef);
            false -> finish(Caller,{error,<<"timeout">>},Conn,CRef,W,WRef)
        end
    end.

%% R3: cleanup is verified FIRST; only then is the result published. An
%% unconfirmed reap fails closed, because the invariant was not established.
finish(Caller,Result,Conn,CRef,W,WRef) ->
    Published = case cleanup(Conn,CRef,W,WRef) of
        confirmed -> Result;
        unconfirmed -> {error, <<"cleanup_unknown">>}
    end,
    Caller ! {http_result,self(),Published},
    exit(normal).

cleanup(Conn,CRef,W,WRef) ->
    exit(W,kill),
    exit(Conn,kill),
    A = await_down(WRef,W),
    B = await_down(CRef,Conn),
    case {A,B} of
        {confirmed,confirmed} -> confirmed;
        _ -> unconfirmed
    end.

await_down(undefined,Pid) ->
    %% Monitor already consumed (conn DOWN observed): confirm liveness directly.
    case is_process_alive(Pid) of false -> confirmed; true -> unconfirmed end;
await_down(Ref,Pid) ->
    receive {'DOWN',Ref,process,Pid,_} -> confirmed
    after ?REAP_BUDGET_MS -> demonitor(Ref,[flush]),
        case is_process_alive(Pid) of false -> confirmed; true -> unconfirmed end
    end.

%% ------------------------------------------------------------------ worker
%% R8 parked until begin; monitors the guardian so it never works for a dead G.
worker_parked(G,Conn,Spec) ->
    GRef = monitor(process,G),
    Deadline = maps:get(deadline,Spec),
    Wait = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {begin_now,G} -> worker(G,GRef,Conn,Spec);
        {'DOWN',GRef,process,G,_} -> exit(normal)
    after Wait -> demonitor(GRef,[flush]), exit(normal)
    end.

worker(G,_GRef,Conn,Spec) ->
    Deadline = maps:get(deadline,Spec),
    %% R14 re-check immediately before the first network call.
    R = case erlang:monotonic_time(millisecond) >= Deadline of
        true -> {error,<<"timeout">>};
        false -> worker_io(Conn,Deadline,Spec)
    end,
    G ! {worker_result,self(),R},
    exit(normal).

worker_io(Conn,Deadline,Spec) ->
    case guarded(fun() -> hackney_conn:connect(Conn, rem_ms(Deadline)) end) of
        {ok_r,ok} -> do_request(Conn,Spec);
        {ok_r,{error,_}} -> {error,<<"connect_failed">>};
        {aborted,_} -> {error,<<"connect_timeout">>}
    end.

rem_ms(Deadline) -> max(1, Deadline - erlang:monotonic_time(millisecond)).

%% R7: no raw term escapes. The reason is discarded, not formatted.
guarded(F) ->
    try F() of V -> {ok_r,V}
    catch exit:{timeout,_} -> {aborted,timeout};
          exit:_ -> {aborted,exited};
          _:_ -> {aborted,crashed} end.

do_request(Conn,Spec) ->
    M=maps:get(method,Spec), P=maps:get(path,Spec),
    H=maps:get(headers,Spec), B=maps:get(body,Spec),
    case guarded(fun() -> hackney_conn:request_async(Conn,M,P,H,B,once,self(),false) end) of
        {ok_r,{ok,Ref}} -> stream(Conn,Ref,Spec,undefined,[],<<>>);
        {ok_r,{error,_}} -> {error,<<"request_failed">>};
        {aborted,timeout} -> {error,<<"timeout">>};
        {aborted,_} -> {error,<<"request_failed">>}
    end.

stream(Conn,Ref,Spec,Status,Hdrs,Acc) ->
    Deadline=maps:get(deadline,Spec), Max=maps:get(max_bytes,Spec),
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    case Remaining =< 0 of
        true -> {error,<<"timeout">>};
        false ->
            receive
                {hackney_response,Ref,{status,S,_}} ->
                    _ = hackney_conn:stream_next(Conn),
                    stream(Conn,Ref,Spec,S,Hdrs,Acc);
                {hackney_response,Ref,{headers,HH}} ->
                    case declared_too_big(HH,Max) of
                        true -> {error,<<"response_payload_exceeds_bound">>};
                        false ->
                            _ = hackney_conn:stream_next(Conn),
                            stream(Conn,Ref,Spec,Status,HH,Acc)
                    end;
                {hackney_response,Ref,done} -> {ok,{Status,Hdrs,Acc}};
                {hackney_response,Ref,{error,timeout}} -> {error,<<"timeout">>};
                {hackney_response,Ref,{error,_}} -> {error,<<"request_failed">>};
                {hackney_response,Ref,Chunk} when is_binary(Chunk) ->
                    New = <<Acc/binary,Chunk/binary>>,
                    case byte_size(New) > Max of
                        true -> {error,<<"response_payload_exceeds_bound">>};
                        false ->
                            _ = hackney_conn:stream_next(Conn),
                            stream(Conn,Ref,Spec,Status,Hdrs,New)
                    end
            after Remaining -> {error,<<"timeout">>}
            end
    end.

declared_too_big(Hdrs,Max) ->
    case cl(Hdrs) of
        {ok,N} -> N > Max;
        none -> false
    end.

cl([]) -> none;
cl([{K,V}|T]) ->
    case string:lowercase(to_list(K)) of
        "content-length" ->
            case string:to_integer(to_list(V)) of
                {N,_} when is_integer(N) -> {ok,N};
                _ -> cl(T)
            end;
        _ -> cl(T)
    end;
cl([_|T]) -> cl(T).

%% Preserved VERBATIM from the current FFI so this module is a true drop-in.
extract_telegram_updates(Body) when is_binary(Body) ->
    try
        case json:decode(Body) of
            #{<<"ok">> := true, <<"result">> := Items} when is_list(Items) ->
                Encoded = [iolist_to_binary(json:encode(I)) || I <- Items],
                {ok, Encoded};
            #{<<"ok">> := false, <<"description">> := Desc} ->
                {error, sanitize_error_description(Desc)};
            _ ->
                {error, <<"invalid_telegram_updates_envelope">>}
        end
    catch
        _:_ ->
            {error, <<"json_decode_failed">>}
    end.

sanitize_error_description(Desc) when is_binary(Desc) ->
    Lower = string:lowercase(Desc),
    case binary:match(Lower, <<"chat not found">>) of
        nomatch ->
            case binary:match(Lower, <<"blocked by the user">>) of
                nomatch ->
                    case binary:match(Lower, <<"user is deactivated">>) of
                        nomatch -> <<"sanitized_rejection">>;
                        _ -> <<"user_deactivated">>
                    end;
                _ -> <<"bot_blocked_by_user">>
            end;
        _ -> <<"chat_not_found">>
    end;
sanitize_error_description(_) -> <<"sanitized_rejection">>.
