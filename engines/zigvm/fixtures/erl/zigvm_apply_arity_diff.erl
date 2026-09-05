%% zigvm_apply_arity_diff — compiled differential for erlang:apply/3 arity
%% (DIVERGENCE 732). `apply(M, F, ArgsList)` where the runtime `ArgsList` has >16
%% elements was `system_limit` on zigvm — the `.apply3` arg-spread loop capped at a
%% STALE `arity >= 16` (a leftover from the pre-E5.2 `[16]` X-register bank; the bank
%% is now `[256]`). Any generic dispatcher / `proc_lib`-style `apply(M,F,Args)` with
%% 17..255 args wrongly crashed. Fixed: crash only at ≥256 (BEAM MAX_ARG=255).
%%
%% VALUE differential: a 17- and a 20-arity function applied to a RUNTIME arg list
%% (lists:seq, not a literal — the compiler would spread a literal to a direct call
%% and mask the apply path). Both VMs return the byte-EQ sums.
%%
%% Run on BOTH VMs (needs stdlib for lists:seq — single --code-path, retry on the
%% autoload heisenbug):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_apply_arity_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_apply_arity_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_apply_arity_diff.beam --code-path third_party/otp/lib/stdlib/ebin t 0
%% Byte-EQ verdict (both): {apply_arity,a17,153,a20,210}
-module(zigvm_apply_arity_diff).
-export([t/1, s17/17, s20/20]).
s17(A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q) -> A+B+C+D+E+F+G+H+I+J+K+L+M+N+O+P+Q.
s20(A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T) -> A+B+C+D+E+F+G+H+I+J+K+L+M+N+O+P+Q+R+S+T.
t(N) ->
    A17 = apply(zigvm_apply_arity_diff, s17, [X + N || X <- lists:seq(1, 17)]),
    A20 = erlang:apply(zigvm_apply_arity_diff, s20, [X + N || X <- lists:seq(1, 20)]),
    erlang:display({apply_arity, a17, A17, a20, A20}).
