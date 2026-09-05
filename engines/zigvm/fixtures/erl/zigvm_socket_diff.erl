%% zigvm_socket_diff — the gen_tcp/gen_udp whole-system DIFFERENTIAL fixture.
%%
%% Runs byte-identically on real pinned OTP-30 and on zigvm; the harness (or a
%% manual run) compiles it with the pinned erlc, executes on both, and diffs the
%% one-line canonical output. This is the live-OTP-30-node differential that
%% admits the `gen_tcp_udp_sockets` capability to EQ (conformance protocol
%% Rule 9 RUNTIME-CAPABILITY-EQUIVALENCE — the OS loopback stack is the oracle).
%%
%% SINGLE-PROCESS SEQUENTIAL flow (no spawn): on loopback the kernel completes
%% the TCP handshake at connect() time, so one process can listen→connect→accept
%% without cross-process scheduling — which keeps it deterministic on zigvm's
%% single-threaded (coarse-locked) scheduler where a blocking accept in a second
%% process would starve the scheduler.
-module(zigvm_socket_diff).
-export([main/0]).

%% Output via erlang:display/1 (a native term dumper that renders binaries
%% identically on both runtimes) rather than io:format — so this stays a clean
%% SOCKET differential, not entangled with io_lib:format's directive surface.
main() ->
    Tcp = tcp_echo(),
    Udp = udp_roundtrip(),
    erlang:display({socket_diff, Tcp, Udp}),
    halt(0).

%% gen_tcp echo: listen(ephemeral) → connect → accept → send → recv → echo → recv.
tcp_echo() ->
    {ok, L} = gen_tcp:listen(0, [binary, {active, false}, {reuseaddr, true}]),
    {ok, Port} = inet:port(L),
    {ok, C} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}]),
    {ok, S} = gen_tcp:accept(L, 2000),
    ok = gen_tcp:send(C, <<"echo-payload-0123456789">>),
    {ok, D} = gen_tcp:recv(S, 0, 2000),
    ok = gen_tcp:send(S, D),
    {ok, Echo} = gen_tcp:recv(C, 0, 2000),
    gen_tcp:close(C),
    gen_tcp:close(S),
    gen_tcp:close(L),
    Echo.

%% gen_udp round-trip: open Rx → learn its port → open Tx → send → recv datagram.
udp_roundtrip() ->
    {ok, Rx} = gen_udp:open(0, [binary, {active, false}]),
    {ok, RxPort} = inet:port(Rx),
    {ok, Tx} = gen_udp:open(0, [binary, {active, false}]),
    ok = gen_udp:send(Tx, {127, 0, 0, 1}, RxPort, <<"udp-datagram-abcXYZ">>),
    {ok, {_Addr, _P, Data}} = gen_udp:recv(Rx, 0, 2000),
    gen_udp:close(Tx),
    gen_udp:close(Rx),
    Data.
