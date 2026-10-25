%% Test-only isolation; never used by the operational CLI.
-module(uos_gate_test_fixture).
-export([with_empty_repository/1, cli_invocation/0]).
with_empty_repository(Fun) ->
    {ok, BeforeCwd} = file:get_cwd(),
    BeforeRoot = os:getenv("UOS_REPO"),
    Root = filename:join("/tmp", "uos-cli-empty-" ++
        integer_to_list(erlang:system_time(microsecond)) ++ "-" ++
        integer_to_list(erlang:unique_integer([positive]))),
    ok = file:make_dir(Root),
    ok = file:change_mode(Root, 8#700),
    try
        ok = file:set_cwd(Root),
        true = os:putenv("UOS_REPO", Root),
        Fun()
    after
        ok = file:set_cwd(BeforeCwd),
        case BeforeRoot of
            false -> os:unsetenv("UOS_REPO");
            Value -> os:putenv("UOS_REPO", Value)
        end,
        ok = file:del_dir(Root)
    end.
cli_invocation() ->
    {main, Beam, _} = code:get_object_code(main),
    Digest = crypto:hash(sha256, Beam),
    Paths = [filename:absname(P) || P <- code:get_path()],
    Expr = io_lib:format(
        "true=code:set_path(~p),{main,B,_}=code:get_object_code(main),"
        "~w=crypto:hash(sha256,B),main:main(),halt(0).", [Paths, Digest]),
    Exe = filename:join([code:root_dir(), "bin", "erl"]),
    {unicode:characters_to_binary(Exe),
     [<<"+S">>, <<"2:2">>, <<"+A">>, <<"2">>, <<"-noshell">>,
      <<"-eval">>, iolist_to_binary(Expr), <<"-extra">>, <<"status">>]}.
