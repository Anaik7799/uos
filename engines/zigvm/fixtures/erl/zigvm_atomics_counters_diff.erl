%% zigvm_atomics_counters_diff — compiled differential for the atomics/counters
%% user-facing modules (DIVERGENCE 726). Exercises `counters:new/2` (atomics
%% backend) + `atomics:new/2` + the op set BY VALUE, so the compiled
%% `erts_internal:atomics_new(Arity, EncodedOpts)` path is proven against the pin,
%% not just the in-process handler.
%%
%% Run on BOTH VMs (counters/atomics are PRELOADED modules -> erts/preloaded/ebin):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_atomics_counters_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_atomics_counters_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_atomics_counters_diff.beam \
%%     --code-path third_party/otp/erts/preloaded/ebin t 0
%% Byte-EQ verdict (both): {cget,12,cput,99,aget,123,aaddget,130}
-module(zigvm_atomics_counters_diff).
-export([t/1]).
t(_) ->
    %% counters — user-facing module, [atomics] backend = {atomics, atomics:new(...)}
    R = counters:new(10, [atomics]),
    counters:add(R, 3, 7),
    counters:add(R, 3, 5),
    V = counters:get(R, 3),          %% 12
    counters:put(R, 5, 99),
    V5 = counters:get(R, 5),         %% 99
    %% atomics — encode_opts([{signed,true}]) -> the ?OPT_SIGNED int bitmask
    A = atomics:new(4, [{signed, true}]),
    atomics:put(A, 2, 100),
    atomics:add(A, 2, 23),
    W = atomics:get(A, 2),           %% 123
    X = atomics:add_get(A, 2, 7),    %% 130
    erlang:display({cget, V, cput, V5, aget, W, aaddget, X}).
