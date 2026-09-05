%% zigvm_apply_fun_diff — compiled differential for erlang:apply/2 (a fun + a
%% RUNTIME arg list) — DIVERGENCE 733. `apply(Fun, Args)` where `Args` is opaque to
%% the compiler (a runtime list, not a literal) compiles to the erlang:apply/2 BIF
%% form, which zigvm had NO handler for → `undef` at all arities. (A literal arg
%% list is spread to a DIRECT fun call at compile time — that path was already EQ,
%% which masked the gap.) Fixed with the `.apply_fun` opcode: spread + dispatch the
%% fun (arity-mismatch → `{badarity,{Fun,Args}}`, non-fun → badarg).
%%
%% VALUE differential: an anonymous closure AND a named fun (`fun M:F/A`) applied to
%% a RUNTIME list (lists:seq), plus the arity-mismatch error shape.
%%
%% Run on BOTH VMs (needs stdlib for lists — single --code-path, retry on autoload):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_apply_fun_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_apply_fun_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_apply_fun_diff.beam --code-path third_party/otp/lib/stdlib/ebin t 0
%% Byte-EQ verdict (both): {apply_fun,anon,321,named,45,badarity,true}
-module(zigvm_apply_fun_diff).
-export([t/1]).
t(N) ->
    Args3 = [X + N || X <- lists:seq(1, 3)],           % runtime list [1,2,3]
    Anon = fun(A, B, C) -> A * 100 + B * 10 + C end,
    Named = fun lists:sum/1,
    Anon321 = erlang:apply(Anon, lists:reverse(Args3)),  % apply(fun/3, [3,2,1]) = 321
    NamedSum = apply(Named, [lists:seq(1, 9)]),          % apply(fun lists:sum/1, [[1..9]]) = 45
    Bad = case catch erlang:apply(Anon, [Z || Z <- lists:seq(1, 2)]) of        % arity mismatch → {badarity,_}
              {'EXIT', {{badarity, _}, _}} -> true;
              _ -> false
          end,
    erlang:display({apply_fun, anon, Anon321, named, NamedSum, badarity, Bad}).
