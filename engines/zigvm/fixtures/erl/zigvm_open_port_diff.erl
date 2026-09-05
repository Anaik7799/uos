%% zigvm_open_port_diff — DIVERGENCE 594, gap-open-port-dispatch (Slice A).
%% The RUNTIME-CAPABILITY-EQUIVALENCE differential for the AUTO-IMPORTED erlang:
%% port verbs + os:cmd/2, reached from a COMPILED beam by their user-facing names
%% (FM-DISPATCH-DEAD #9: they were wired only under module erts_internal). Renders
%% byte-IDENTICALLY on zigvm and on pinned OTP-30 (679f9dbb). Run each clause on
%% both VMs; the erlang:display output must match line-for-line.
-module(zigvm_open_port_diff).
-export([t/1]).

%% os:cmd/1 + os:cmd/2 (the os.erl wrappers over the live-port seam).
t(1) -> erlang:display(os:cmd("echo hello_oscmd"));
t(2) -> erlang:display(os:cmd("echo two", #{}));

%% DEFAULT `list` mode: {Port,{data,Charlist}} — the mode the cat round-trip
%% surfaced (was wrongly a binary before the fix).
t(3) -> P = open_port({spawn,"cat"},[]),
        port_command(P,"ping\n"),
        R = receive {P,{data,D}} -> {list_mode,D} after 1000 -> list_timeout end,
        port_close(P),
        erlang:display(R);

%% `binary` mode: {Port,{data,Binary}}.
t(4) -> P = open_port({spawn,"cat"},[binary]),
        port_command(P,"pong\n"),
        R = receive {P,{data,D}} -> {binary_mode,D} after 1000 -> bin_timeout end,
        port_close(P),
        erlang:display(R);

%% ports/0 membership + port_info name (observed representation-free).
t(5) -> P = open_port({spawn,"cat"},[]),
        Member = lists:member(P, erlang:ports()),
        {name,Nm} = erlang:port_info(P, name),
        port_close(P),
        erlang:display({member,Member,name,Nm});

%% a bad port rejects (badarg), not a false success.
t(6) -> R = try port_command(list_to_atom("not_a_port"),"x")
            catch error:badarg -> caught_badarg end,
        erlang:display(R).
