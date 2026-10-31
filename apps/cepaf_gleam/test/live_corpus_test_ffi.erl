-module(live_corpus_test_ffi).
-export([fixture/1, symlink/2, hardlink/2, fifo/1, parallel/1, restart_workers/0, swap_race/2]).
fixture(Fun) ->
    reset_test_gateway(),
    Root = <<"/tmp/uos-live-corpus-test-", (integer_to_binary(erlang:system_time(nanosecond)))/binary,
             "-", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
    Previous = os:getenv("UOS_MCP_WORKSPACE_ROOT"),
    ok = file:make_dir(Root), os:putenv("UOS_MCP_WORKSPACE_ROOT", binary_to_list(Root)),
    try Fun(Root)
    after reset_test_gateway(),
          case Previous of false -> os:unsetenv("UOS_MCP_WORKSPACE_ROOT"); _ -> os:putenv("UOS_MCP_WORKSPACE_ROOT", Previous) end,
          file:del_dir_r(Root)
    end.
symlink(Target, Link) -> file:make_symlink(Target, Link), nil.
hardlink(Target, Link) -> file:make_link(Target, Link), nil.
fifo(Path) -> os:cmd("mkfifo " ++ binary_to_list(Path)), nil.
parallel(Fun) ->
    Jobs = [spawn_monitor(fun() -> Fun(I) end) || I <- lists:seq(1,32)],
    lists:all(fun({_Pid, Ref}) -> receive {'DOWN',Ref,process,_,normal} -> true;
        {'DOWN',Ref,process,_,_} -> false after 15000 -> false end end, Jobs).
restart_workers() ->
    case persistent_term:get(uos_mcp_runtime_gateway_subject, none) of
        {some, Subject} ->
            {ok, Pid} = 'gleam@erlang@process':subject_owner(Subject),
            Ref = monitor(process, Pid), exit(Pid, kill),
            receive {'DOWN', Ref, process, Pid, _} -> ok after 1000 -> error(owner_did_not_die) end,
            await_replacement(Pid, 200), 1;
        _ -> 0
    end.
await_replacement(_Old, 0) -> error(owner_did_not_restart);
await_replacement(Old, N) ->
    case persistent_term:get(uos_mcp_runtime_gateway_subject, none) of
        {some, Subject} -> case 'gleam@erlang@process':subject_owner(Subject) of
            {ok, Pid} when Pid =/= Old -> case is_process_alive(Pid) of
                true -> ok; false -> receive after 5 -> await_replacement(Old, N-1) end end;
            _ -> receive after 5 -> await_replacement(Old, N-1) end
        end;
        _ -> receive after 5 -> await_replacement(Old, N-1) end
    end.

%% Confined to this EUnit VM. No external/live service is signalled.
reset_test_gateway() ->
    case whereis(uos_mcp_runtime_gateway_sup) of
        P when is_pid(P) -> Ref = monitor(process,P), exit(P,kill),
            receive {'DOWN',Ref,process,P,_} -> ok after 1000 -> error(test_supervisor_alive) end;
        _ -> ok
    end,
    case persistent_term:get(uos_mcp_runtime_gateway_subject,none) of
        {some,{subject,Owner,_}} when is_pid(Owner) ->
            case is_process_alive(Owner) of true -> exit(Owner,kill); false -> ok end;
        _ -> ok
    end,
    persistent_term:erase(uos_mcp_runtime_gateway_subject), ok.

%% Race an intermediate directory against a foreign target in the hermetic root.
%% The reader must return local bytes or refuse, never the foreign bytes.
swap_race(Root, Read) ->
    Dir = <<Root/binary,"/docs/wiki/raced">>,
    Saved = <<Root/binary,"/saved-race">>,
    Outside = <<Root/binary,"/outside">>,
    {Pid, Ref} = spawn_monitor(fun() -> swap_loop(Dir, Saved, Outside) end),
    try lists:foreach(fun(_) -> Read() end, lists:seq(1,500)), true
    after exit(Pid,kill), receive {'DOWN',Ref,process,Pid,_} -> ok after 1000 -> error(racer_alive) end,
      case file:read_link_info(Dir) of {ok,I} when element(3,I) =:= symlink -> file:delete(Dir); _ -> ok end,
      case file:read_link_info(Saved) of {ok,_} -> file:rename(Saved,Dir); _ -> ok end
    end.
swap_loop(Dir, Saved, Outside) ->
    case file:rename(Dir,Saved) of
      ok -> file:make_symlink(Outside,Dir), erlang:yield(), file:delete(Dir), file:rename(Saved,Dir);
      _ -> ok
    end,
    erlang:yield(), swap_loop(Dir,Saved,Outside).
