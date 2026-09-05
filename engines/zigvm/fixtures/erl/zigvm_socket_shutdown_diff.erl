%% zigvm_socket_shutdown_diff — the gen_tcp:shutdown/2 half-close DIFFERENTIAL.
%%
%% Runs byte-identically on real pinned OTP-30 and on zigvm; the harness (or a
%% manual run) compiles it with the pinned erlc, executes on both, and diffs the
%% one-line canonical output. This extends the `gen_tcp_udp_sockets` EQ surface
%% with the graceful half-close (conformance Rule 9 RUNTIME-CAPABILITY-EQUIVALENCE
%% — the OS loopback stack is the oracle for the orderly-EOF semantics).
%%
%% SINGLE-PROCESS SEQUENTIAL flow (no spawn) — on loopback the kernel completes
%% the handshake at connect() time, keeping it deterministic on zigvm's
%% single-threaded scheduler (see zigvm_socket_diff for the rationale).
-module(zigvm_socket_shutdown_diff).
-export([main/0]).

%% Output via erlang:display/1 (identical binary/tuple rendering on both runtimes).
main() ->
    erlang:display({shutdown_diff, half_close()}),
    halt(0).

%% The graceful half-close: the client sends P then shutdown(write). The server
%% MUST still drain P (buffered data survives the half-close), and the NEXT recv
%% sees the orderly EOF the shutdown delivered → {error, closed}. The canonical
%% result pairs the drained payload with that EOF reason.
half_close() ->
    {ok, L} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true}]),
    {ok, Port} = inet:port(L),
    {ok, C} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}]),
    {ok, S} = gen_tcp:accept(L, 2000),
    ok = gen_tcp:send(C, <<"graceful-half-close-payload-9876">>),
    ok = gen_tcp:shutdown(C, write),
    {ok, Drained} = gen_tcp:recv(S, byte_size(<<"graceful-half-close-payload-9876">>), 2000),
    Eof = gen_tcp:recv(S, 1, 2000),
    gen_tcp:close(C),
    gen_tcp:close(S),
    gen_tcp:close(L),
    {Drained, Eof}.
