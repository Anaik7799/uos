%% Test-only independent OS-process driver for session_sync durability checks.
-module(session_sync_test_ffi).
-export([workspace_alias/0, run_cli/2, run_cli_pair/3, child_cli/0]).

-define(MAX_OUTPUT, 1048576).

workspace_alias() ->
    Base = filename:join(<<"/tmp">>, <<"uos-session-workspace-", (unique_id())/binary>>),
    Real = filename:join(Base, <<"real">>),
    Alias = filename:join(Base, <<"alias">>),
    ok = file:make_dir(Base),
    ok = file:make_dir(Real),
    ok = file:make_symlink(<<"real">>, Alias),
    {Real, Alias}.

run_cli(Args, Fault) ->
    Port = start_cli(Args, Fault),
    collect(Port, <<>>).

run_cli_pair(ArgsA, ArgsB, Fault) ->
    PortA = start_cli(ArgsA, Fault),
    PortB = start_cli(ArgsB, Fault),
    {StatusA, OutputA} = collect(PortA, <<>>),
    {StatusB, OutputB} = collect(PortB, <<>>),
    {StatusA, OutputA, StatusB, OutputB}.

start_cli(Args, Fault) ->
    Erl = os:find_executable("erl"),
    {ok, Cwd} = file:get_cwd(),
    Ebins = filelib:wildcard(filename:join([Cwd, "build", "dev", "erlang", "*", "ebin"])),
    Paths = lists:append([["-pa", Path] || Path <- Ebins]),
    Payload = base64:encode(term_to_binary({Args, Fault})),
    ErlArgs = ["+S", "2:2", "+A", "2", "-noshell"] ++ Paths ++
        ["-s", "session_sync_test_ffi", "child_cli", "-extra", binary_to_list(Payload)],
    open_port({spawn_executable, Erl}, [binary, exit_status, stderr_to_stdout,
        use_stdio, hide, {cd, Cwd}, {args, ErlArgs}]).

collect(Port, Output) when byte_size(Output) =< ?MAX_OUTPUT ->
    receive
        {Port, {data, Bytes}} -> collect(Port, <<Output/binary, Bytes/binary>>);
        {Port, {exit_status, Code}} -> {Code, Output}
    after 5000 ->
        catch port_close(Port),
        {124, <<Output/binary, "test child timed out">>}
    end;
collect(Port, Output) ->
    catch port_close(Port),
    {125, binary:part(Output, 0, ?MAX_OUTPUT)}.

child_cli() ->
    [Encoded] = init:get_plain_arguments(),
    {Args, Fault} = binary_to_term(base64:decode(Encoded), [safe]),
    case Fault of
        <<>> -> ok;
        _ -> put('$session_sync_test_fault', Fault)
    end,
    case session_sync_cli:run(Args) of
        {ok, Output} -> io:put_chars([Output, <<"\n">>]), erlang:halt(0);
        {error, Error} -> io:put_chars([Error, <<"\n">>]), erlang:halt(1)
    end.

unique_id() -> binary:encode_hex(crypto:strong_rand_bytes(12), lowercase).
