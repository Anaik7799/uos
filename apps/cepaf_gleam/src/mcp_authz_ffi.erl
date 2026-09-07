%% Minimal, dependency-free helpers for MCP tool-call authorization.
%% Rate-limit state lives in the calling process dictionary: the stdio server
%% loop and each Zenoh bridge handler are single processes, so the counter is
%% per serving process, per calendar minute. No ETS, no shell, no network.
-module(mcp_authz_ffi).
-export([get_env/1, rate_state_get/0, rate_state_put/1, window_key/0, now_iso8601/0]).

get_env(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.

rate_state_get() ->
    case erlang:get(uos_mcp_rate_state) of
        undefined -> {error, nil};
        State -> {ok, State}
    end.

rate_state_put(State) ->
    erlang:put(uos_mcp_rate_state, State),
    nil.

window_key() ->
    integer_to_binary(erlang:system_time(second) div 60).

now_iso8601() ->
    {{Y, Mo, D}, {H, Mi, S}} = calendar:now_to_universal_time(erlang:timestamp()),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, Mo, D, H, Mi, S])).
