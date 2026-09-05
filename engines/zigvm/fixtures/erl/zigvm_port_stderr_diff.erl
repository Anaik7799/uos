%% zigvm_port_stderr_diff — Slice D, gap-open-port-stderr.
%% The RUNTIME-CAPABILITY-EQUIVALENCE differential for the `stderr_to_stdout`
%% open-port option: the child's stderr (fd 2) is MERGED into the port's single
%% data stream (fd2→fd1 dup at spawn). Composes with {line,N} and exit_status and
%% binary. Byte-IDENTICAL on zigvm and pinned OTP-30. Avoids lists:* (bare-CLI safe).
-module(zigvm_port_stderr_diff).
-export([t/1]).

%% stdout + stderr merged into one data stream.
t(1) -> collect(open_port({spawn,"sh -c 'echo out; echo err 1>&2'"},[stderr_to_stdout,exit_status]));
%% merged stream framed by {line,N}.
t(2) -> collect(open_port({spawn,"sh -c 'echo aa; echo bb 1>&2'"},[stderr_to_stdout,{line,80},exit_status]));
%% a pure-stderr producer is captured (would be lost without the option).
t(3) -> collect(open_port({spawn,"sh -c 'echo onlyerr 1>&2'"},[stderr_to_stdout,exit_status]));
%% merged stream in binary mode.
t(4) -> collect(open_port({spawn,"sh -c 'printf ab; printf cd 1>&2'"},[stderr_to_stdout,binary,exit_status])).

collect(P) -> collect(P,[]).
collect(P,Acc) ->
    receive
        {P,{data,D}}        -> collect(P,[D|Acc]);
        {P,{exit_status,S}} -> erlang:display({frames,rev(Acc,[]),{exit_status,S}})
    after 1200 -> erlang:display({frames,rev(Acc,[]),timeout})
    end.
rev([],A)->A; rev([H|T],A)->rev(T,[H|A]).
