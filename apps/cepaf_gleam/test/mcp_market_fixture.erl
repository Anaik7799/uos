%% Test-only subprocess and allocation observations. No admission/effect authority.
-module(mcp_market_fixture).
-export([fault_survival/0,heap_benchmark/0,write_schema_report/1]).

root() -> "/home/an/NAS-setup/uos".
evidence(Name) -> filename:join([root(),"var/harness/20261030-2325-mcp-resilience",Name]).
write_schema_report(B) -> case file:write_file(evidence("market-53-schema-results.json"),B) of
    ok -> {ok,nil}; {error,E} -> {error,err(E)} end.
err(E) -> iolist_to_binary(io_lib:format("~p",[E])).

fault_survival() ->
    Erl=filename:join([code:root_dir(),"bin","erl"]),
    Paths=lists:append([["-pa",P] || P<-code:get_path(),filelib:is_dir(P)]),
    Expr="io:setopts([{encoding,utf8}]), 'cepaf_gleam@mcp@runtime_gateway':stdio_main(), halt(0).",
    P=open_port({spawn_executable,Erl},[binary,use_stdio,exit_status,{line,1048576},
        {cd,root()}, {env,[{"ERL_CRASH_DUMP_SECONDS","0"},{"ERL_FLAGS",""},
        {"UOS_MCP_ZENOH_SUBSCRIBER","0"},{"UOS_MCP_ROUTE","public"},
        {"UOS_MCP_ACTOR_ID","codex"},{"UOS_MCP_CLIENT_NAME","market-fault"},
        {"UOS_MCP_WORKSPACE_ROOT",root()}]},
        {args,["+S","1:1","+A","1","-noshell","-noinput"]++Paths++["-eval",Expr]}]),
    Started=erlang:monotonic_time(millisecond),
    try
        {os_pid,OsPid}=erlang:port_info(P,os_pid),
        send_error(P,<<255,10>>,-32700),
        send_error(P,<<(binary:copy(<<"x">>,1100000))/binary,10>>,-32600),
        send_error(P,<<"{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"ping\",\"x\":\"\\u0000\"}\n">>,-32600),
        send_error(P,<<"{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"ping\",\"method\":\"tools/list\"}\n">>,-32600),
        send_error(P,<<"{broken\n">>,-32700),
        send_result(P,<<"{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\",\"capabilities\":{}}}\n">>,6),
        true=port_command(P,<<"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n">>),
        receive {P,{data,_}} -> error(notification_emitted_bytes);
                {P,{exit_status,S0}} -> error({notification_killed_child,S0})
        after 100 -> ok end,
        send_result(P,<<"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}\n">>,7),
        Health=send_result(P,<<"{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"system_health\",\"arguments\":{}}}\n">>,8),
        #{<<"result">>:=#{<<"isError">>:=false}}=Health,
        {os_pid,OsPid}=erlang:port_info(P,os_pid),
        Out=#{status=><<"PASS">>,single_os_process=>true,os_pid=>OsPid,
              rejected_frames=>5,notification_emitted_bytes=>0,
              initialize=>true,ping=>true,system_health=>true,
              elapsed_ms=>erlang:monotonic_time(millisecond)-Started,
              scope=><<"Real local development stdio process; not official rmcp SDK execution">>},
        ok=file:write_file(evidence("market-stdio-fault-survival.json"),json:encode(Out)),
        {ok,nil}
    catch C:E -> {error,err({C,E})}
    after try port_close(P) catch _:_ -> ok end,
          receive {P,{exit_status,_}}->ok after 0->ok end end.

send_error(P,B,Code) ->
    true=port_command(P,B),
    #{<<"error">>:=#{<<"code">>:=Code}}=Response=read_frame(P),
    true=maps:is_key(<<"id">>,Response),
    ok.
send_result(P,B,Id) ->
    true=port_command(P,B),
    V=read_frame(P),
    #{<<"id">>:=Id,<<"result">>:=_}=V,
    V.
read_frame(P) ->
    receive
        {P,{data,{eol,B}}} -> json:decode(B);
        {P,{data,{noeol,_}}} -> error(unbounded_stdout_frame);
        {P,{exit_status,S}} -> error({child_exited,S})
    after 1500 -> error(stdio_response_timeout) end.

heap_benchmark() ->
    try
        Payload=binary:copy(<<"x">>,262144),
        Frame= <<"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"payload\":\"",Payload/binary,"\"}}">>,
        {Legacy,LR}=measure(legacy,Frame),
        {Native,NR}=measure(native,Frame),
        Ratio=Legacy/Native,
        Receipt=#{status=>case Ratio>=5 of true-><<"PASS">>;false-><<"FAIL">> end,
          observed_at=>list_to_binary(calendar:system_time_to_rfc3339(erlang:system_time(second),[{unit,second},{offset,"Z"}])),
          frame_bytes=>byte_size(Frame),payload_bytes=>262144,
          legacy_heap_words=>Legacy,native_heap_words=>Native,heap_reduction_ratio=>Ratio,
          legacy_reductions=>LR,native_reductions=>NR,minimum_ratio=>5,
          legacy_path=><<"gleam/string.to_graphemes retained depth-scan input">>,
          native_path=><<"OTP29 json:decode/3 strict guard and retained parsed value">>,
          scope=><<"Isolated worker total_heap_size after materialization, not OS RSS or global VM memory">>},
        ok=file:write_file(evidence("json-otp29-benchmark.json"),json:encode(Receipt)),
        {ok,{Legacy,Native}}
    catch C:E -> {error,err({C,E})} end.
measure(Kind,Frame) ->
    Parent=self(),Tag=make_ref(),
    {Pid,Mon}=spawn_monitor(fun()->
        erlang:garbage_collect(),
        {reductions,Before}=process_info(self(),reductions),
        V=case Kind of legacy -> 'gleam@string':to_graphemes(Frame);
                       native -> {ok,Tree}=mcp_stdio_ffi:mcp_json_strict_inspect(Frame,32),Tree end,
        {total_heap_size,Words}=process_info(self(),total_heap_size),
        {reductions,After}=process_info(self(),reductions),
        %% Keeping the materialized result live prevents an optimizing compiler
        %% dropping the allocation before the observation.
        Check=case Kind of legacy->length(V);native->element(1,V) end,
        Parent!{Tag,{Words,After-Before},Check}
    end),
    receive
        {Tag,Result,_}->demonitor(Mon,[flush]),Result;
        {'DOWN',Mon,process,Pid,Why}->error({benchmark_worker_failed,Why})
    after 2500 ->exit(Pid,kill),demonitor(Mon,[flush]),error(benchmark_timeout) end.
