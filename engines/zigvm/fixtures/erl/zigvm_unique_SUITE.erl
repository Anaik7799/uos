%% Curated PURE subset of erts/emulator/test/unique_SUITE.erl (E7 suite
%% closure). The real suite is a WHITE-BOX probe of the unique-integer
%% machinery: it moves erts_debug internal counter state across the small/big
%% and sint64 boundaries on a peer node and checks exact values, and it
%% reconstructs the thread-id/counter bit layout via
%% erts_debug:get_internal_state({make_unique_integer,..}). None of that is
%% portable (erts_debug, peer, spawn, exact values are creation-dependent).
%% These cases mirror the suite's INTENT as BLACK-BOX PROPERTIES of
%% erlang:unique_integer/0,1 that OTP documents and zigvm computes
%% identically: every call yields a fresh integer (uniqueness within a
%% modifier set), [monotonic] is strictly increasing across calls,
%% [positive] yields only integers > 0, modifier order is irrelevant,
%% [] behaves as no modifiers, and non-list / unknown / improper option
%% arguments raise error:badarg. NEVER exact values, NEVER sign of the
%% default (no-modifier) variant (OTP's default counter starts deep
%% negative; zigvm's starts positive — both are valid under the documented
%% contract, so only documented properties are asserted). Every option list
%% is routed through the EXPORTED ?MODULE:id/1 — an external call erlc
%% cannot inline or constant-fold — so the RUNTIME BIF argument path is
%% exercised. No ct/port/node/spawn/io/timing dependency — runnable directly
%% on the zigvm CLI byte-EQ vs OTP-30.
-module(zigvm_unique_SUITE).
-export([all/0, id/1, c_two_calls_differ/1, c_default_loop_unique/1,
         c_empty_opts/1, c_monotonic_increasing/1, c_monotonic_loop_unique/1,
         c_positive/1, c_positive_loop_unique/1, c_positive_monotonic/1,
         c_opts_order/1, c_badarg/1]).

all() ->
    [c_two_calls_differ, c_default_loop_unique, c_empty_opts,
     c_monotonic_increasing, c_monotonic_loop_unique, c_positive,
     c_positive_loop_unique, c_positive_monotonic, c_opts_order, c_badarg].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call — the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% Uniqueness, minimal form: two successive calls with the same (empty)
%% modifier set yield two DIFFERENT integers.
c_two_calls_differ(_) ->
    X = erlang:unique_integer(),
    Y = erlang:unique_integer(),
    is_integer(X) andalso is_integer(Y) andalso (X =/= Y).

%% Uniqueness over a short loop: 40 default-modifier values are pairwise
%% distinct (the suite's "never return the same integer more than once"
%% contract, black-box).
c_default_loop_unique(_) ->
    Vs = collect(40, none),
    all_integers(Vs) andalso distinct(Vs).

%% [] is the empty modifier set: same contract as unique_integer/0 —
%% integers, fresh on every call.
c_empty_opts(_) ->
    A = erlang:unique_integer(?MODULE:id([])),
    B = erlang:unique_integer(?MODULE:id([])),
    is_integer(A) andalso is_integer(B) andalso (A =/= B).

%% [monotonic]: strictly increasing across 30 successive calls (the
%% white-box suite's strict-monotonic counter property, without touching
%% the counter state).
c_monotonic_increasing(_) ->
    P0 = erlang:unique_integer(?MODULE:id([monotonic])),
    is_integer(P0) andalso mono_incr(30, P0).

%% Strict monotonicity implies uniqueness — assert it independently over a
%% collected monotonic run (and that the run's last value exceeds a fresh
%% earlier probe).
c_monotonic_loop_unique(_) ->
    First = erlang:unique_integer(?MODULE:id([monotonic])),
    Vs = collect(25, [monotonic]),
    Later = erlang:unique_integer(?MODULE:id([monotonic])),
    all_integers(Vs) andalso distinct(Vs) andalso (Later > First).

%% [positive]: only integers > 0, on every call.
c_positive(_) ->
    X = erlang:unique_integer(?MODULE:id([positive])),
    Y = erlang:unique_integer(?MODULE:id([positive])),
    is_integer(X) andalso is_integer(Y)
        andalso (X > 0) andalso (Y > 0) andalso (X =/= Y).

%% [positive] over a loop: all > 0 and pairwise distinct.
c_positive_loop_unique(_) ->
    Vs = collect(40, [positive]),
    all_integers(Vs) andalso all_positive(Vs) andalso distinct(Vs).

%% [positive, monotonic]: strictly increasing AND strictly positive across
%% successive calls.
c_positive_monotonic(_) ->
    P0 = erlang:unique_integer(?MODULE:id([positive, monotonic])),
    is_integer(P0) andalso (P0 > 0) andalso pos_mono_incr(20, P0).

%% Modifier ORDER is irrelevant: [monotonic, positive] denotes the same
%% modifier set as [positive, monotonic] — accepted, positive, and
%% increasing between two successive calls.
c_opts_order(_) ->
    A = erlang:unique_integer(?MODULE:id([monotonic, positive])),
    B = erlang:unique_integer(?MODULE:id([monotonic, positive])),
    is_integer(A) andalso is_integer(B)
        andalso (A > 0) andalso (B > A).

%% Rejection: a non-list argument, an unknown modifier atom, an unknown
%% modifier hiding behind a valid one, a non-atom list element, and an
%% improper option tail all raise error:badarg (class-discriminated try —
%% supported and EQ; the bare reason, never the stack).
c_badarg(_) ->
    badarg_probe(?MODULE:id(not_a_list))
        andalso badarg_probe(?MODULE:id(17))
        andalso badarg_probe(?MODULE:id([bogus]))
        andalso badarg_probe(?MODULE:id([positive, bogus]))
        andalso badarg_probe(?MODULE:id([1]))
        andalso badarg_probe(?MODULE:id([positive | monotonic])).

%% ── helpers (no stdlib dependency) ──────────────────────────────────────

badarg_probe(Arg) ->
    try erlang:unique_integer(Arg) of
        _ -> false
    catch
        error:badarg -> true;
        _:_ -> false
    end.

mono_incr(0, _Prev) -> true;
mono_incr(N, Prev) when N > 0 ->
    X = erlang:unique_integer(?MODULE:id([monotonic])),
    (X > Prev) andalso mono_incr(N - 1, X).

pos_mono_incr(0, _Prev) -> true;
pos_mono_incr(N, Prev) when N > 0 ->
    X = erlang:unique_integer(?MODULE:id([positive, monotonic])),
    (X > 0) andalso (X > Prev) andalso pos_mono_incr(N - 1, X).

collect(N, Opts) -> collect(N, Opts, []).

collect(0, _Opts, Acc) -> Acc;
collect(N, Opts, Acc) when N > 0 ->
    V = case Opts of
            none -> erlang:unique_integer();
            _ -> erlang:unique_integer(?MODULE:id(Opts))
        end,
    collect(N - 1, Opts, [V | Acc]).

all_integers([]) -> true;
all_integers([H | T]) -> is_integer(H) andalso all_integers(T).

all_positive([]) -> true;
all_positive([H | T]) -> (H > 0) andalso all_positive(T).

distinct([]) -> true;
distinct([H | T]) -> (not member(H, T)) andalso distinct(T).

member(_X, []) -> false;
member(X, [H | T]) -> (X =:= H) orelse member(X, T).
