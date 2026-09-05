%% zigvm_port_line_diff — Slice C, gap-open-port-line.
%% The RUNTIME-CAPABILITY-EQUIVALENCE differential for the `{line, N}` open-port
%% option: a child's output is framed into {Port,{data,{eol|noeol,Line}}} messages
%% — a complete line → {eol,Line} (terminator stripped); a line longer than N →
%% {noeol,N-bytes} chunks with the final ≤N piece {eol,_}; an unterminated EOF tail
%% → {noeol,tail}. Composes with exit_status (Slice B) and binary mode (Slice A).
%% Byte-IDENTICAL on zigvm and pinned OTP-30. Avoids lists:* (bare-CLI safe).
-module(zigvm_port_line_diff).
-export([t/1]).

%% two complete lines → [{eol,"a"},{eol,"b"}].
t(1) -> collect(open_port({spawn,"printf 'a\\nb\\n'"},[{line,80}]));
%% an unterminated final tail → {noeol,_}.
t(2) -> collect(open_port({spawn,"printf 'x\\ny'"},[{line,80}]));
%% a line LONGER than N → {noeol,N} then the terminated remainder {eol,_}.
t(3) -> collect(open_port({spawn,"printf 'abcdef\\n'"},[{line,3}]));
%% {line,N} + exit_status → frames then {exit_status,0} (Slice B compose).
t(4) -> collect(open_port({spawn,"printf 'p\\nq\\n'"},[{line,80},exit_status]));
%% {line,N} + binary → {eol,Binary} (Slice A compose).
t(5) -> collect(open_port({spawn,"printf 'bin\\n'"},[{line,80},binary])).

collect(P) -> collect(P,[]).
collect(P,Acc) ->
    receive
        {P,{data,{eol,L}}}   -> collect(P,[{eol,L}|Acc]);
        {P,{data,{noeol,L}}} -> collect(P,[{noeol,L}|Acc]);
        {P,{exit_status,S}}  -> emit(Acc,{exit_status,S})
    after 800 -> emit(Acc,timeout)
    end.
emit(Acc,Tail) -> erlang:display({frames,rev(Acc,[]),Tail}).
rev([],A)->A; rev([H|T],A)->rev(T,[H|A]).
