%% zigvm_port_exit_status_diff — Slice B, gap-open-port-exit-status.
%% The RUNTIME-CAPABILITY-EQUIVALENCE differential for the `exit_status` open-port
%% option: an AUTONOMOUS-PRODUCER child ({spawn,"echo done"}) delivers
%% {Port,{data,Out}} then, IF `exit_status` was given, {Port,{exit_status,Code}};
%% the message is NOT delivered on an explicit port_close (a `cat` filter), nor at
%% all without the option. Renders byte-IDENTICALLY on zigvm and pinned OTP-30.
%% Avoids lists:* so it runs on the bare CLI (both VMs collect in receive order).
-module(zigvm_port_exit_status_diff).
-export([t/1]).

%% (1) autonomous producer + exit_status: {data,_} then {exit_status,0}.
t(1) -> P = open_port({spawn,"echo done"},[exit_status]),
        collect(P, undefined);

%% (2) NONZERO exit code is reported verbatim.
t(2) -> P = open_port({spawn,"sh -c 'echo hi; exit 3'"},[exit_status]),
        collect(P, undefined);

%% (3) exit_status + binary mode: data is a binary, exit_status still fires.
t(3) -> P = open_port({spawn,"echo bin"},[exit_status,binary]),
        collect(P, undefined);

%% (4) a `cat` filter + exit_status: data on command; NO exit_status on port_close.
t(4) -> P = open_port({spawn,"cat"},[exit_status]),
        port_command(P,"echo\n"),
        R1 = receive {P,{data,D}} -> {data,D} after 500 -> nodata end,
        port_close(P),
        R2 = receive {P,{exit_status,S}} -> {es,S} after 300 -> no_es_after_close end,
        erlang:display({R1,R2});

%% (5) NO exit_status option: producer data delivered, but NO exit_status message.
t(5) -> P = open_port({spawn,"echo noopt"},[]),
        R1 = receive {P,{data,D}} -> {data,D} after 500 -> nodata end,
        R2 = receive {P,{exit_status,S}} -> {es,S} after 200 -> no_es_msg end,
        erlang:display({R1,R2}).

%% collect the data frame then the exit_status frame (no lists:*).
collect(P, Data) ->
    receive
        {P,{data,D}}        -> collect(P, D);
        {P,{exit_status,S}} -> erlang:display({exit_status,S,data,Data})
    after 1500 -> erlang:display({timeout,data,Data})
    end.
