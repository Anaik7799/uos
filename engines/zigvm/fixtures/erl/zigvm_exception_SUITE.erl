%% Curated PURE subset of erts/emulator/test/exception_SUITE.erl (E7 suite
%% closure). The real suite exercises exception raising/catching: badmatch
%% reporting, pending errors after suppressed guard failures, nil arithmetic
%% (badarith on non-numbers), stacktrace tops, erlang:raise/3, class-change
%% rethrow (gunilla/per/change_exception_class), backtrace depth, and
%% error_info metadata — driven by ct, spawned processes, catch-expression
%% {'EXIT',{Reason,Stk}} shapes and stacktrace contents. These cases MIRROR the
%% pure algebraic core of badmatch, pending_errors (bad_guy's reason ladder,
%% incl. a suppressed-guard-badarith first clause), nil_arith (ba_plus_minus_
%% times/ba_div_rem/ba_bop/ba_shift/ba_bnot), per (t1/t2 bsl badarith), the
%% foo/1 error/throw/exit class arms, gunilla's class+reason observation, and
%% change_exception_class's class-change-sticks law (via a plain erlang:error
%% rethrow in a catch clause — NO erlang:raise) as self-contained BOOLEAN
%% assertions over try...catch Class:Reason patterns. Bare REASON shapes only:
%% badarith, {badmatch,V}, {case_clause,V}, if_clause, function_clause, throw
%% pass-through values, exit reasons — all EQ on zigvm. EXCLUDED: stacktrace
%% contents and the catch-wrap {'EXIT',{Reason,Stk}} shape (documented
%% divergence: zigvm lands the BARE reason, stacktraces nil), erlang:raise/3,
%% system_flag(backtrace_depth), undef/timeout_value/spawn-badarg rows (module
%% resolution / receive-after / spawn dependencies), error/2,3 arg-annotated
%% stacktraces, exception_with_heap_frag (ETF fuzz driver), line_numbers. All
%% runtime operands are routed through the EXPORTED ?MODULE:id/1 so erlc
%% cannot constant-fold the failing expression under test. No ct/port/node/io
%% dependency — runnable directly on the zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_exception_SUITE).
-export([all/0, id/1, c_badmatch/1, c_pending_errors/1, c_case_clause/1,
         c_if_clause/1, c_function_clause/1, c_nil_arith/1, c_nil_bitwise/1,
         c_div_zero/1, c_try_class/1, c_throw_passthrough/1, c_exit_reason/1,
         c_change_class/1, c_per/1]).

all() ->
    [c_badmatch, c_pending_errors, c_case_clause, c_if_clause,
     c_function_clause, c_nil_arith, c_nil_bitwise, c_div_zero, c_try_class,
     c_throw_passthrough, c_exit_reason, c_change_class, c_per].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call — the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% Class discrimination observer (the foo/1 arms as a total observation):
%% a normal value, or the {Class, Reason} that escaped — try...catch
%% Class:Reason patterns only, never the catch-expression wrap shape.
classify(F) ->
    try F() of
        V -> {value, V}
    catch
        throw:T -> {throw, T};
        error:E -> {error, E};
        exit:X -> {exit, X}
    end.

is_badarith(F) -> classify(F) =:= {error, badarith}.

%% badmatch/1 (?try_match): a deliberately failed match of each literal
%% pattern shape (atom, small, tuple, nil, float) against id(nomatch) reports
%% error:{badmatch, nomatch}; a compound pattern carries the actual value.
c_badmatch(_) ->
    (classify(fun() -> a = ?MODULE:id(nomatch) end)
        =:= {error, {badmatch, nomatch}})
        andalso (classify(fun() -> 42 = ?MODULE:id(nomatch) end)
                 =:= {error, {badmatch, nomatch}})
        andalso (classify(fun() -> {a, b, c} = ?MODULE:id(nomatch) end)
                 =:= {error, {badmatch, nomatch}})
        andalso (classify(fun() -> [] = ?MODULE:id(nomatch) end)
                 =:= {error, {badmatch, nomatch}})
        andalso (classify(fun() -> 1.0 = ?MODULE:id(nomatch) end)
                 =:= {error, {badmatch, nomatch}})
        andalso (classify(fun() -> {ok, _V} = ?MODULE:id({error, 42}) end)
                 =:= {error, {badmatch, {error, 42}}}).

%% pending_errors/1: the bad_guy reason ladder — each body error carries its
%% canonical bare reason, in the presence of a PRECEDING clause whose guard
%% error (atom + 1) was suppressed into a quiet clause fall-through; an
%% unmatched argument lands function_clause.
c_pending_errors(_) ->
    (classify(fun() -> bad_guy(?MODULE:id(e_badmatch)) end)
        =:= {error, {badmatch, b}})
        andalso (classify(fun() -> bad_guy(?MODULE:id(e_case)) end)
                 =:= {error, {case_clause, xxx}})
        andalso (classify(fun() -> bad_guy(?MODULE:id(e_if)) end)
                 =:= {error, if_clause})
        andalso (classify(fun() -> bad_guy(?MODULE:id(e_badarith)) end)
                 =:= {error, badarith})
        andalso (classify(fun() -> bad_guy(?MODULE:id(x)) end)
                 =:= {error, function_clause}).

bad_guy(A) when A + 1 == 0 -> unreachable;      % badarith (suppressed)
bad_guy(e_case) ->
    case ?MODULE:id(xxx) of
        ok -> ok
    end;                                        % {case_clause, xxx}
bad_guy(e_if) ->
    X = ?MODULE:id(a),
    if
        X == b -> ok
    end;                                        % if_clause
bad_guy(e_badarith) ->
    ?MODULE:id(1) + ?MODULE:id(b);              % badarith
bad_guy(e_badmatch) ->
    a = ?MODULE:id(b).                          % {badmatch, b}

%% e_case (value-carrying): {case_clause, V} carries the exact scrutinee —
%% atom, compound, and map values — while a matching scrutinee is normal.
c_case_clause(_) ->
    (cc(?MODULE:id(ok)) =:= matched)
        andalso (classify(fun() -> cc(?MODULE:id(xxx)) end)
                 =:= {error, {case_clause, xxx}})
        andalso (classify(fun() -> cc(?MODULE:id({a, [1, 2]})) end)
                 =:= {error, {case_clause, {a, [1, 2]}}})
        andalso (classify(fun() -> cc(?MODULE:id(#{k => 1})) end)
                 =:= {error, {case_clause, #{k => 1}}}).

cc(V) ->
    case V of
        ok -> matched
    end.

%% e_if: if_clause is a BARE atom (no value payload) whenever no branch
%% condition holds, for any unmatched input type.
c_if_clause(_) ->
    (iff(?MODULE:id(1)) =:= one)
        andalso (iff(?MODULE:id(2)) =:= two)
        andalso (classify(fun() -> iff(?MODULE:id(3)) end)
                 =:= {error, if_clause})
        andalso (classify(fun() -> iff(?MODULE:id(banan)) end)
                 =:= {error, if_clause}).

iff(X) ->
    if
        X == 1 -> one;
        X == 2 -> two
    end.

%% raise/1's odd/even ladder (sans raise/stacktrace): a mutually recursive
%% local pair whose domain gap lands function_clause — from the missing base
%% clause (odd(0)) and from a failed guard (negative / wrong parity input).
c_function_clause(_) ->
    (even(?MODULE:id(8)) =:= ok)
        andalso (classify(fun() -> even(?MODULE:id(9)) end)
                 =:= {error, function_clause})
        andalso (classify(fun() -> odd(?MODULE:id(0)) end)
                 =:= {error, function_clause})
        andalso (classify(fun() -> even(?MODULE:id(-2)) end)
                 =:= {error, function_clause}).

even(0) -> ok;
even(N) when is_integer(N), N > 0 -> odd(N - 1).

odd(N) when is_integer(N), N > 0 -> even(N - 1).

%% nil_arith/1 (ba_plus_minus_times + ba_div_rem rows): +, -, *, /, div, rem
%% on [] against nil/small/bignum/float operands all raise badarith, on
%% either side.
c_nil_arith(_) ->
    Nil = ?MODULE:id([]),
    Sm = ?MODULE:id(42),
    Big = ?MODULE:id(38724978123478923784),
    Fl = ?MODULE:id(38.72),
    is_badarith(fun() -> Nil + Nil end)
        andalso is_badarith(fun() -> Nil + Sm end)
        andalso is_badarith(fun() -> Nil + Big end)
        andalso is_badarith(fun() -> Nil + Fl end)
        andalso is_badarith(fun() -> Sm - Nil end)
        andalso is_badarith(fun() -> Big - Nil end)
        andalso is_badarith(fun() -> Fl * Nil end)
        andalso is_badarith(fun() -> Nil * Big end)
        andalso is_badarith(fun() -> Nil / Sm end)
        andalso is_badarith(fun() -> Sm div Nil end)
        andalso is_badarith(fun() -> Nil rem Sm end).

%% nil_arith/1 (ba_bop + ba_bnot + ba_shift rows): band/bor/bxor/bnot/bsl/bsr
%% on [] or floats raise badarith — bitwise ops are integer-only.
c_nil_bitwise(_) ->
    Nil = ?MODULE:id([]),
    Sm = ?MODULE:id(23),
    Big = ?MODULE:id(2438724982478933),
    Fl = ?MODULE:id(23.33),
    is_badarith(fun() -> Nil band Sm end)
        andalso is_badarith(fun() -> Sm bor Nil end)
        andalso is_badarith(fun() -> Nil bxor Big end)
        andalso is_badarith(fun() -> bnot Nil end)
        andalso is_badarith(fun() -> bnot Fl end)
        andalso is_badarith(fun() -> Nil bsl 4 end)
        andalso is_badarith(fun() -> Nil bsr -4 end)
        andalso is_badarith(fun() -> Sm bsl Nil end)
        andalso is_badarith(fun() -> Fl bsl 1 end)
        andalso is_badarith(fun() -> Big bsr Nil end).

%% Division by zero is badarith for /, div and rem — small and bignum
%% dividends alike (the focus row: badarith from 1/0).
c_div_zero(_) ->
    One = ?MODULE:id(1),
    Zero = ?MODULE:id(0),
    Big = ?MODULE:id(1180591620717411303424),   % 1 bsl 70
    is_badarith(fun() -> One / Zero end)
        andalso is_badarith(fun() -> One div Zero end)
        andalso is_badarith(fun() -> One rem Zero end)
        andalso is_badarith(fun() -> Big div Zero end)
        andalso is_badarith(fun() -> Big rem Zero end).

%% foo/1's value/error/throw/exit arms: try...catch Class:Reason
%% discrimination is total — each class lands ONLY in its own clause, and a
%% normal value takes the of-branch.
c_try_class(_) ->
    (classify(fun() -> ?MODULE:id(ok) end) =:= {value, ok})
        andalso (classify(fun() -> throw(kalle) end) =:= {throw, kalle})
        andalso (classify(fun() -> erlang:throw(?MODULE:id({a, 1})) end)
                 =:= {throw, {a, 1}})
        andalso (classify(fun() -> erlang:error(pelle) end)
                 =:= {error, pelle})
        andalso (classify(fun() -> erlang:exit(arne) end) =:= {exit, arne})
        andalso (classify(fun() -> exit(?MODULE:id(bye)) end)
                 =:= {exit, bye}).

%% Thrown values pass through intermediate call frames UNCHANGED (deep
%% compound term: tuple + list + map), whatever the call depth.
c_throw_passthrough(_) ->
    T = ?MODULE:id({tag, [1, 2, 3], #{k => v}}),
    R1 = try deep_throw(3, T) catch throw:X1 -> X1 end,
    R2 = try outer_call(T) catch throw:X2 -> X2 end,
    (R1 =:= T) andalso (R2 =:= T).

deep_throw(0, T) -> erlang:throw(T);
deep_throw(N, T) when is_integer(N), N > 0 -> deep_throw(N - 1, T).

outer_call(T) -> deep_throw(1, T).

%% exit/1 inside the raising process is catchable with its exact reason —
%% including exit(normal) (only the SIGNAL form is uncatchable) and compound
%% reasons.
c_exit_reason(_) ->
    (classify(fun() -> exit(normal) end) =:= {exit, normal})
        andalso (classify(fun() -> exit({shutdown, ?MODULE:id(5)}) end)
                 =:= {exit, {shutdown, 5}})
        andalso (classify(fun() -> exit(?MODULE:id([a, {b, 2}])) end)
                 =:= {exit, [a, {b, 2}]}).

%% change_exception_class/1 (sans raw_raise): an inner catch clause that
%% rethrows a throw as erlang:error(Reason) CHANGES the class, and the change
%% sticks — the outer try observes error, never throw (gunilla's class+reason
%% observation, via a plain BIF rethrow instead of erlang:raise/3).
c_change_class(_) ->
    (cec(fun() -> throw(arne) end) =:= {outer, error, arne})
        andalso (cec(fun() -> erlang:error(ove) end) =:= {outer, error, ove})
        andalso (cec(fun() -> ?MODULE:id(ok) end) =:= ok).

cec(F) ->
    try cec_inner(F) of
        V -> V
    catch
        C:R -> {outer, C, R}
    end.

cec_inner(F) ->
    try F() of
        V -> V
    catch
        throw:R -> erlang:error(R)
    end.

%% per/1: bsl with a non-integer operand (t1: 1 bsl pad; t2: pad bsl 1)
%% raises badarith from inside a called function, while integer operands
%% compute normally.
c_per(_) ->
    (t1(?MODULE:id(3)) =:= 9)
        andalso (t2(?MODULE:id(3)) =:= 7)
        andalso (classify(fun() -> t1(?MODULE:id(pad)) end)
                 =:= {error, badarith})
        andalso (classify(fun() -> t2(?MODULE:id(pad)) end)
                 =:= {error, badarith}).

t1(X) -> (1 bsl X) + 1.
t2(X) -> (X bsl 1) + 1.
