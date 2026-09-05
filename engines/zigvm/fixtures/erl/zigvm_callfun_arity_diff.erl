%% zigvm_callfun_arity_diff — compiled differential for the call_fun/call_fun2 arity
%% check (DIVERGENCE 734). A CLOSURE called with the wrong number of arguments must
%% raise `error:{badarity,{Fun,Args}}`. zigvm's `.call_fun`/`.call_fun2` opcodes did
%% NOT validate the arg count against the closure's arity — they jumped to the fun
%% body anyway, running it with garbage/missing args (→ `badarith`/a wrong result).
%% A compile-time `apply(Fun3, [1,2])` (LITERAL list) is inlined by the compiler to a
%% direct 2-arg fun call (`call_fun2/2`), so it exercises this path (distinct from
%% DIVERGENCE 733's `apply/2` opcode, which is the runtime-list form).
%%
%% VALUE differential: a /3 closure applied to a literal 2-list → badarity; a MATCHING
%% call still returns the value.
%%
%% Run on BOTH VMs (no stdlib needed):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_callfun_arity_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_callfun_arity_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_callfun_arity_diff.beam t 0
%% Byte-EQ verdict (both): {callfun_arity,ok,321,badarity,true}
-module(zigvm_callfun_arity_diff).
-export([t/1]).
t(_) ->
    F3 = fun(A, B, C) -> A * 100 + B * 10 + C end,
    Ok = apply(F3, [3, 2, 1]),                         % literal 3-list → direct call, EQ = 321
    Bad = case catch apply(F3, [1, 2]) of              % literal 2-list → call_fun2/2, mismatch
              {'EXIT', {{badarity, _}, _}} -> true;
              _ -> false
          end,
    erlang:display({callfun_arity, ok, Ok, badarity, Bad}).
