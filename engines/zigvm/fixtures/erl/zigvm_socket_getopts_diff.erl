%% zigvm_socket_getopts_diff — the inet:getopts/2 read-back DIFFERENTIAL.
%%
%% Runs byte-identically on real pinned OTP-30 and on zigvm; the harness (or a
%% manual run) compiles it with the pinned erlc, executes on both, and diffs the
%% one-line canonical output. Extends the `gen_tcp_udp_sockets` EQ surface with
%% the setopts→getopts round-trip for the `active` option (the option zigvm
%% models truthfully). Conformance Rule 9 RUNTIME-CAPABILITY-EQUIVALENCE.
%%
%% SINGLE-PROCESS SEQUENTIAL (no spawn) — loopback completes the handshake at
%% connect() time (see zigvm_socket_diff for the rationale).
-module(zigvm_socket_getopts_diff).
-export([main/0]).

main() ->
    erlang:display({getopts_diff, active_roundtrip()}),
    halt(0).

%% setopts records {active, once}; getopts reads EXACTLY it back. The canonical
%% result is the getopts proplist for [active] — {ok, [{active, once}]} on both.
active_roundtrip() ->
    {ok, L} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true}]),
    {ok, Port} = inet:port(L),
    {ok, C} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}]),
    {ok, S} = gen_tcp:accept(L, 2000),
    ok = inet:setopts(C, [{active, once}]),
    {ok, Opts} = inet:getopts(C, [active]),
    gen_tcp:close(C),
    gen_tcp:close(S),
    gen_tcp:close(L),
    Opts.
