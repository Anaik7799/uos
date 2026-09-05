%% zigvm_seq_io_diff — the SEQUENTIAL fd op differential (gap-file-seq-io,
%% DIVERGENCE 589). file:read/2 + write/2 + position/2 over the RunFd tracked
%% offset, byte-identical on pinned OTP-30 and zigvm. Run from a writable CWD:
%%   erlc -o D f.erl; erl -noshell -pa D -run zigvm_seq_io_diff g ; zigvm run f.beam g
-module(zigvm_seq_io_diff).
-export([g/0]).
g() ->
    F = "zseq_diff.dat",
    {ok, W} = file:open(F, [write, raw, binary]),
    ok = file:write(W, <<"HELLO">>),
    ok = file:write(W, <<"world">>),            % sequential append (offset advances)
    file:close(W),
    {ok, R} = file:open(F, [read, raw, binary]),
    erlang:display({read5,       file:read(R, 5)}),          % {ok,<<"HELLO">>}
    erlang:display({pos_cur,     file:position(R, {cur, 0})}),% {ok,5}
    erlang:display({read_rest,   file:read(R, 100)}),        % {ok,<<"world">>}
    erlang:display({read_eof,    file:read(R, 1)}),          % eof
    erlang:display({pos_int,     file:position(R, 3)}),      % {ok,3}
    erlang:display({read_at3,    file:read(R, 2)}),          % {ok,<<"LO">>}
    erlang:display({pos_eof_neg, file:position(R, {eof, -4})}),% {ok,6}
    erlang:display({read_tail,   file:read(R, 100)}),        % {ok,<<"orld">>}
    erlang:display({pos_neg,     file:position(R, {bof, -1})}),% {error,einval}
    file:close(R),
    halt(0).
