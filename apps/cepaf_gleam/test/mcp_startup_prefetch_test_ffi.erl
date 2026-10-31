%% Fresh-VM regression: startup does no SQL; first planning request observes it.
-module(mcp_startup_prefetch_test_ffi).
-export([run/0,probe_main/0]).
probe_main() ->
    G='cepaf_gleam@mcp@runtime_gateway',
    {module,G}=code:ensure_loaded(G),
    {module,mcp_stdio_ffi}=code:ensure_loaded(mcp_stdio_ffi),
    true=lists:prefix("/home/an/NAS-setup/uos/apps/cepaf_gleam/build/dev/erlang/",
        code:which(mcp_stdio_ffi)),
    MFA={mcp_stdio_ffi,run_workspace_bounded_cd,4},
    1=erlang:trace_pattern(MFA,true,[call_count]),
    _=erlang:trace(all,true,[call,set_on_spawn]),
    Root= <<"/home/an/NAS-setup/uos">>,Plan= <<"20261030-2325-mcp-resilience-perf-scale-bdd-fractal">>,
    Call=fun(Method,Params,Id)->
        Raw=iolist_to_binary(json:encode(#{jsonrpc=><<"2.0">>,id=>Id,method=>Method,params=>Params})),
        {some,Reply}=G:handle_standard_mcp_line(<<"startup-budget">>,<<"codex">>,Root,
            <<"startup-budget-fresh-vm">>,<<"public">>,Raw,erlang:system_time(millisecond)),
        json:decode(Reply)
    end,
    #{<<"result">>:=#{<<"protocolVersion">>:= <<"2026-07-28">>}}=
        Call(<<"initialize">>,#{protocolVersion=><<"2026-07-28">>,capabilities=>#{}},1),
    #{<<"result">>:=#{<<"tools">>:=Tools}}=Call(<<"tools/list">>,#{},2),
    53=length(Tools),true=G:is_running(),
    {call_count,InitCalls}=erlang:trace_info(MFA,call_count),
    io:format("STARTUP_SQL_PROBE ~s~n",[json:encode(#{bounded_commands_before_planning=>InitCalls})]),
    0=InitCalls,
    Db= <<Root/binary,"/var/sa-plan/uos.sqlite3">>,
    Query= <<"SELECT count(*) FROM sa_plan_task WHERE plan_id='",Plan/binary,"';">>,
    {ok,{0,CountText}}=mcp_stdio_ffi:run_workspace_bounded_cd(<<"/usr/bin/sqlite3">>,
        [<<"-readonly">>,<<"-cmd">>,<<".timeout 1000">>,Db,Query],Root,1500),
    Expected=binary_to_integer(string:trim(CountText)),
    {call_count,BeforeRead}=erlang:trace_info(MFA,call_count),
    #{<<"result">>:=#{<<"isError">>:=false,<<"structuredContent">>:=
        #{<<"canonical_authority">>:= <<"sa_plan">>,<<"plan_id">>:=Plan,
          <<"total_tasks">>:=Expected}}}=Call(<<"tools/call">>,
            #{name=><<"plan_status">>,arguments=>#{plan_id=>Plan}},3),
    {call_count,AfterRead}=erlang:trace_info(MFA,call_count),
    true=AfterRead>BeforeRead,
    io:format("STARTUP_SQL_PROBE ~s~n",[json:encode(#{status=><<"PASS">>,
        initialize_and_tools_list_bounded_commands=>InitCalls,
        first_planning_request_bounded_commands=>AfterRead-BeforeRead,
        canonical_plan=>Plan,total_tasks=>Expected})]),
    halt(0).

%% The existing bounded native process guardian owns timeout/output/reaping.
run() ->
    Root="/home/an/NAS-setup/uos",
    Erl=list_to_binary(filename:join([code:root_dir(),"bin","erl"])),
    Own=filename:dirname(code:which(?MODULE)),
    Bins=lists:usort([Own|[P || P<-code:get_path(),filelib:is_dir(P),
        lists:prefix(Root++"/apps/cepaf_gleam/build/",P)]]),
    Paths=lists:append([[<<"-pa">>,list_to_binary(P)] || P<-Bins]),
    Args=[<<"ERL_FLAGS=">>,<<"ERL_CRASH_DUMP=/dev/null">>,
          <<"UOS_MCP_WORKSPACE_ROOT=/home/an/NAS-setup/uos">>,
          <<"ERL_CRASH_DUMP_SECONDS=0">>,<<"UOS_MCP_ZENOH_SUBSCRIBER=0">>,
          Erl,<<"+S">>,<<"2:2">>,<<"+A">>,<<"2">>,<<"-noinput">>,<<"-noshell">>]++
          Paths++[<<"-s">>,<<"mcp_startup_prefetch_test_ffi">>,<<"probe_main">>],
    case mcp_stdio_ffi:run_workspace_bounded_cd(<<"/usr/bin/env">>,Args,list_to_binary(Root),15000) of
        {ok,{0,Out}} ->
            ok=file:write_file(Root++"/var/harness/20261030-2325-mcp-resilience/R07-startup-prefetch-last-child.log",Out),
            case binary:match(Out,<<"\"status\":\"PASS\"">>) of
                nomatch->{error,<<"Fresh VM omitted planning proof">>};
                _->{ok,nil}
            end;
        {ok,{Code,Out}} -> {error,iolist_to_binary(["Fresh VM exit ",integer_to_binary(Code),": ",Out])};
        {error,Reason} -> {error,Reason}
    end.
