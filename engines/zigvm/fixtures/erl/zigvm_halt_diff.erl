%% zigvm_halt_diff — the erlang:halt/0,1,2 EXIT-CODE differential fixture
%% (gap-halt-dispatch, DIVERGENCE 584). Each entry function displays a marker
%% then halts; the OBSERVABLE is the OS exit code (the oracle node dies with the
%% call, so — like open_port/os:cmd — it's a subprocess-level differential, not
%% an in-VM return value). Run each on both runtimes and compare $?:
%%   erlc -o D f.erl
%%   erl -noshell -pa D -run zigvm_halt_diff h7 ; echo $?     %% → 7
%%   zig-out/bin/zigvm run f.beam h7 ; echo $?                %% → 7
%% Verified byte-EQ vs pinned OTP-30 679f9dbb: h0=0 h1=0 h7=7 habort=134
%% hslogan=1 hbig=44 (300 mod 256, erts exit-code truncation).
%% gap-halt-argcheck (DIVERGENCE 585): the halting cases below are the exit-code
%% differential; `rejects/0` is the ARGUMENT-VALIDATION differential — every
%% invalid Status raises a CATCHABLE badarg (the node stays alive), byte-EQ vs
%% OTP-30. Run `... -run zigvm_halt_diff rejects` on both and diff stdout.
-module(zigvm_halt_diff).
-export([h0/0, h1/0, h7/0, habort/0, hslogan/0, hbig/0, rejects/0]).

h0() -> erlang:display(halting), halt(0).
h1() -> erlang:display(halting), halt().          % halt/0 == halt(0)
h7() -> erlang:display(halting), halt(7).
habort() -> erlang:display(halting), halt(abort). % SIGABRT convention → 134
hslogan() -> erlang:display(halting), halt("crashdump slogan"). % → exit 1 (slogan to STDERR)
hbig() -> erlang:display(halting), halt(300).     % capped: 300 mod 256 = 44

%% Each invalid Status must raise a catchable badarg (not terminate the node).
rejects() ->
    Bad = [-1, foo, true, 1.5, {a, b}, <<"bin">>, [16#110000], [$a, -1], [65 | 66]],
    lists:foreach(
        fun(V) ->
            R = try erlang:halt(V) of X -> {no_raise, X} catch C:E -> {C, E} end,
            erlang:display(R)                        % expect {error,badarg} for every V
        end, Bad),
    halt(0).
