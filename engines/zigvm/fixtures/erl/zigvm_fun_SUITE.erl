%% Curated PURE subset of erts/emulator/test/fun_SUITE.erl (E7 suite closure).
%% The real suite exercises fun construction, is_function/1,2, arity, apply,
%% closure capture, equality and ordering. This curated subset keeps ONLY the
%% representation-independent truths that both VMs compute identically and that
%% zigvm can construct+apply on the CLI: local funs, closures over captured
%% environments, is_function/1, is_function/2 with a legal small arity, direct
%% call vs apply/2 agreement, and self-application recursion. It DELIBERATELY
%% EXCLUDES everything rep-dependent or unsupported: fun equality/ordering
%% (identity), phash/phash2 values, md5, fun_info/fun_to_list (internal rep),
%% external funs, ports/nodes/spawn, and bad-arity exception paths.
-module(zigvm_fun_SUITE).
-export([all/0, c_is_function1/1, c_is_function1_neg/1, c_is_function2/1,
         c_is_function2_neg/1, c_arity/1, c_apply_local/1, c_closure_nullary/1,
         c_closure_transform/1, c_closure_distinct/1, c_self_recursion/1,
         c_fun_in_guard/1, c_higher_order/1]).

%% c_closure_distinct RE-ADDED (fix-closure-aliasing, 2026-07-23): it had
%% surfaced a REAL zigvm bug — `{G1(),G2()}` returned `{#Fun,#Fun}` instead of
%% `{1,2}` because (1) the loader stored the FunT TOTAL arity instead of erts's
%% `arity - num_free` (generators.tab MakeFun), and (2) `call_fun`/`call_fun2`
%% never restored the closure env into x[arity..arity+num_free) (the BEAM
%% fun-entry convention, erts beam_common.c call_fun). Both fixed; DIVERGENT→EQ.
all() ->
    [c_is_function1, c_is_function1_neg, c_is_function2, c_is_function2_neg,
     c_arity, c_apply_local, c_closure_nullary, c_closure_transform,
     c_closure_distinct, c_self_recursion, c_fun_in_guard, c_higher_order].

%% is_function/1 is true for funs of every constructible arity.
c_is_function1(_) ->
    is_function(fun() -> ok end)
        andalso is_function(fun(X) -> X end)
        andalso is_function(fun(X, Y) -> X + Y end)
        andalso is_function(fun(X, Y, Z) -> X + Y + Z end).

%% is_function/1 is false for every non-fun term (mirrors t_is_function2 negs).
c_is_function1_neg(_) ->
    (not is_function(42))
        andalso (not is_function({a, b}))
        andalso (not is_function({a, b, c}))
        andalso (not is_function([a, b, c]))
        andalso (not is_function([]))
        andalso (not is_function(<<1, 2>>))
        andalso (not is_function(an_atom)).

%% is_function/2: true exactly when the fun's arity matches the second arg.
c_is_function2(_) ->
    is_function(fun() -> ok end, 0)
        andalso is_function(fun(_) -> ok end, 1)
        andalso is_function(fun(_, _) -> ok end, 2)
        andalso is_function(fun(_, _, _) -> ok end, 3).

%% is_function/2: false for a mismatched arity or a non-fun (mirrors t_is_function2).
c_is_function2_neg(_) ->
    (not is_function(fun(_) -> ok end, 0))
        andalso (not is_function(fun() -> ok end, 1))
        andalso (not is_function(fun(_, _) -> ok end, 1))
        andalso (not is_function({a, b}, 0))
        andalso (not is_function([a, b, c], 0))
        andalso (not is_function(42, 0)).

%% arity is observable through is_function/2 across 0..3 (mirrors t_arity).
c_arity(_) ->
    F0 = fun() -> ok end,
    F1 = fun(A) -> A + 1 end,
    F2 = fun(A, B) -> A + B end,
    F3 = fun(A, B, C) -> A + B + C end,
    is_function(F0, 0) andalso (not is_function(F0, 1))
        andalso is_function(F1, 1) andalso (not is_function(F1, 2))
        andalso is_function(F2, 2) andalso (not is_function(F2, 0))
        andalso is_function(F3, 3) andalso (not is_function(F3, 2)).

%% Applying a local fun via apply/2 agrees with the direct call (mirrors spawn_call).
c_apply_local(_) ->
    F0 = fun() -> 41 + 1 end,
    F1 = fun(X) -> X * 2 end,
    F2 = fun(X, Y) -> X + Y end,
    (apply(F0, []) =:= F0())
        andalso (apply(F1, [21]) =:= F1(21))
        andalso (apply(F2, [3, 4]) =:= F2(3, 4))
        andalso (F0() =:= 42)
        andalso (F1(21) =:= 42)
        andalso (F2(3, 4) =:= 7).

%% A nullary closure captures a value from its defining environment (make_fun/1).
c_closure_nullary(_) ->
    X = 17,
    G = fun() -> X end,
    (G() =:= 17) andalso is_function(G, 0).

%% A closure over two captured values computes A*X+Y (mirrors make_fun/2 in ordering).
c_closure_transform(_) ->
    Mk = fun(Xc, Yc) -> fun(A) -> A * Xc + Yc end end,
    F = Mk(3, 4),
    (F(0) =:= 4) andalso (F(1) =:= 7) andalso (F(10) =:= 34)
        andalso is_function(F, 1).

%% Closures over distinct environments produce distinct results (make_fun(1) vs (2)).

%% Self-application recursion (Y-combinator style) — only plain closures + apply.
%% Two closures built from the same enclosing fun carry DISTINCT immutable
%% environments (the fix-closure-aliasing regression case: escapes through
%% variables so the compiler cannot beta-reduce the applications away).
c_closure_distinct(_) ->
    Mk = fun(N) -> fun() -> N end end,
    G1 = Mk(1),
    G2 = Mk(2),
    (G1() =:= 1) andalso (G2() =:= 2) andalso (G1() =/= G2()).

c_self_recursion(_) ->
    Fact = fun(Self, N) ->
                   case N of
                       0 -> 1;
                       _ -> N * Self(Self, N - 1)
                   end
           end,
    (Fact(Fact, 0) =:= 1)
        andalso (Fact(Fact, 5) =:= 120)
        andalso (Fact(Fact, 10) =:= 3628800).

%% is_function/2 works as a guard test (mirrors the t_is_function2 guard block).
%% Terms flow through id/1 so the guards are evaluated at runtime, not folded.
c_fun_in_guard(_) ->
    F1 = id(fun(_) -> ok end),
    N = id(42),
    R1 = if is_function(F1, 1) -> yes; true -> no end,
    R2 = if is_function(F1, 0) -> yes; true -> no end,
    R3 = if is_function(N, 0) -> yes; true -> no end,
    (R1 =:= yes) andalso (R2 =:= no) andalso (R3 =:= no).

%% Funs passed as arguments to a higher-order helper (map/fold over a list).
c_higher_order(_) ->
    Double = fun(X) -> X * 2 end,
    Add = fun(X, Acc) -> X + Acc end,
    (mymap(Double, [1, 2, 3]) =:= [2, 4, 6])
        andalso (myfold(Add, 0, [1, 2, 3, 4]) =:= 10)
        andalso (mymap(fun(X) -> X * X end, [1, 2, 3, 4]) =:= [1, 4, 9, 16]).

mymap(_F, []) -> [];
mymap(F, [H | T]) -> [F(H) | mymap(F, T)].

myfold(_F, Acc, []) -> Acc;
myfold(F, Acc, [H | T]) -> myfold(F, F(H, Acc), T).

id(X) -> X.
