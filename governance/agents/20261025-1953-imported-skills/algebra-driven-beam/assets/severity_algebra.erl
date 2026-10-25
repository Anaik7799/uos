%%% TEMPLATE: minimal complete ADD module for the BEAM (OTP 24+).
%%% Domain: alert Severity — a bounded semilattice under "worst wins".
%%% To adapt: replace the domain + [[.]] equations, keep the file shape and
%%% law suite intact. Semantic domain:
%%%   [[Severity]] ≙ level()  (ordered; combine = max)
%%%   [[none]] = ok    [[at(L)]] = L    [[worst(A,B)]] = max([[A]], [[B]])
-module(severity_algebra).
-export([max_level/2, verify_signature/1,
         gen_severity/3, verify_semilattice_laws/2, verify_homomorphism/3]).
-export_type([level/0]).
-include_lib("eunit/include/eunit.hrl").

-type level() :: ok | warn | error | fatal.

%% ---- PART 1: SIGNATURE ----
-callback none() -> term().
-callback at(level()) -> term().
-callback worst(term(), term()) -> term().
-callback level(term()) -> level().        %% the observation
-callback eql(term(), term()) -> boolean().

verify_signature(Mod) ->
    case code:ensure_loaded(Mod) of
        {module, Mod} -> ok;
        {error, Why} -> error({signature_violation, Mod, {not_loadable, Why}})
    end,
    Req = [{none,0},{at,1},{worst,2},{level,1},{eql,2}],
    case [FA || {F,A}=FA <- Req, not erlang:function_exported(Mod, F, A)] of
        [] -> ok;
        Missing -> error({signature_violation, Mod, {missing_exports, Missing}})
    end.

%% ---- PART 2: SEMANTIC DOMAIN (order on levels) ----
rank(ok) -> 0; rank(warn) -> 1; rank(error) -> 2; rank(fatal) -> 3.
max_level(A, B) -> case rank(A) >= rank(B) of true -> A; false -> B end.

%% ---- PART 4: LAWS (encodings live in severity_initial / severity_final) ----
levels() -> [ok, warn, error, fatal].

gen_level(S0) ->
    {I, S1} = rand:uniform_s(4, S0),
    {lists:nth(I, levels()), S1}.

gen_severity(Mod, 0, S0) ->
    case rand:uniform_s(2, S0) of
        {1, S1} -> {Mod:none(), S1};
        {2, S1} -> {L, S2} = gen_level(S1), {Mod:at(L), S2}
    end;
gen_severity(Mod, Depth, S0) ->
    case rand:uniform_s(3, S0) of
        {1, S1} -> {Mod:none(), S1};
        {2, S1} -> {L, S2} = gen_level(S1), {Mod:at(L), S2};
        {3, S1} -> {A, S2} = gen_severity(Mod, Depth - 1, S1),
                   {B, S3} = gen_severity(Mod, Depth - 1, S2),
                   {Mod:worst(A, B), S3}
    end.

defaults(C) -> maps:merge(#{iterations => 200, max_depth => 5, seed => 16#ADD0CAFE}, C).

expect_law(true, _N, _C, _I) -> ok;
expect_law(false, Name, #{seed := Seed, max_depth := D}, I) ->
    io:format("LAW FAILED: ~s (seed=~.16B, iteration=~b, depth=~b)~n", [Name, Seed, I, D]),
    error({law_failed, Name, #{seed => Seed, iteration => I}}).

verify_semilattice_laws(Mod, Cfg0) ->
    ok = verify_signature(Mod),
    Cfg = #{iterations := N, max_depth := D, seed := Seed} = defaults(Cfg0),
    lists:foldl(
      fun(I, S0) ->
          {X, S1} = gen_severity(Mod, D, S0),
          {Y, S2} = gen_severity(Mod, D, S1),
          {Z, S3} = gen_severity(Mod, D, S2),
          E = Mod:none(),
          expect_law(Mod:eql(Mod:worst(E, X), X), "left identity", Cfg, I),
          expect_law(Mod:eql(Mod:worst(X, E), X), "right identity", Cfg, I),
          expect_law(Mod:eql(Mod:worst(Mod:worst(X, Y), Z),
                             Mod:worst(X, Mod:worst(Y, Z))), "associativity", Cfg, I),
          expect_law(Mod:eql(Mod:worst(X, Y), Mod:worst(Y, X)), "commutativity", Cfg, I),
          expect_law(Mod:eql(Mod:worst(X, X), X), "idempotence", Cfg, I),
          S3
      end, rand:seed_s(exsss, {Seed, Seed, Seed}), lists:seq(1, N)),
    ok.

verify_homomorphism(ModA, ModB, Cfg0) ->
    ok = verify_signature(ModA), ok = verify_signature(ModB),
    #{iterations := N, max_depth := D, seed := Seed} = defaults(Cfg0),
    S = rand:seed_s(exsss, {Seed, Seed, Seed}),
    lists:foldl(
      fun(_, {SA0, SB0}) ->
          {TA, SA1} = gen_severity(ModA, D, SA0),
          {TB, SB1} = gen_severity(ModB, D, SB0),
          true = (ModA:level(TA) =:= ModB:level(TB)),
          {SA1, SB1}
      end, {S, S}, lists:seq(1, N)),
    ok.

initial_laws_test_() ->
    {timeout, 60, fun() -> ok = verify_semilattice_laws(severity_initial, #{}) end}.
final_laws_test_() ->
    {timeout, 60, fun() -> ok = verify_semilattice_laws(severity_final, #{}) end}.
homomorphism_test_() ->
    {timeout, 60, fun() -> ok = verify_homomorphism(severity_initial, severity_final, #{}) end}.
doctrine_guard_test() ->
    X = severity_initial:at(warn),
    W = severity_initial:worst(severity_initial:none(), X),
    ?assertNotEqual(W, X),                    %% structurally different
    ?assert(severity_initial:eql(W, X)).      %% observationally equal
