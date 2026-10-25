%%% canvas_algebra: Algebra-Driven Design reference for the BEAM (OTP 24+).
%%% Spatial Canvas domain — signature (behaviour), semantic domain, generic
%%% property-based law suite, homomorphism check, doctrine-guard tests.
%%%
%%% Semantic domain:  [[Canvas]] ≙ {X, Y} -> pixel() | transparent
%%%   Represented as a map with absent keys = transparent, over an 8x8 grid,
%%%   so equality is total (whole domain), canonical, and free (`=:=`).
%%%   [[empty]]          = #{}
%%%   [[fill(Px)]]       = every cell -> Px
%%%   [[overlay(T, B)]]  = per cell: T's pixel if painted, else B's
%%%                        (maps:merge(B, T) — the denotation IS the stdlib op)
%%%
%%% Doctrine rule 1: laws are judged OBSERVATIONALLY via rasterize/eql, never
%%% on term structure — {overlay, empty, X} is structurally distinct from X
%%% yet lawfully equal to it.

-module(canvas_algebra).

%% Semantic domain
-export([blank/0, uniform/1, over/2, raster_eql/2]).
%% Signature contract
-export([verify_signature/1]).
%% Generator + law suites (generic over the implementation module)
-export([gen_canvas/3, verify_monoid_laws/2, verify_homomorphism/3]).

-export_type([pixel/0, raster/0, law_config/0]).

-include_lib("eunit/include/eunit.hrl").

-define(GRID_W, 8).
-define(GRID_H, 8).

-type pixel()  :: {0..255, 0..255, 0..255}.
-type raster() :: #{{non_neg_integer(), non_neg_integer()} => pixel()}.
-type law_config() :: #{iterations => pos_integer(),
                        max_depth  => non_neg_integer(),
                        seed       => integer()}.

%%% ==========================================================================
%%% PART 1: THE SIGNATURE — behaviour callbacks + runtime contract
%%% ==========================================================================

-callback empty() -> term().
-callback fill(pixel()) -> term().
-callback overlay(Top :: term(), Bottom :: term()) -> term().
-callback rasterize(term()) -> raster().        %% the observation [[.]]
-callback eql(term(), term()) -> boolean().     %% MUST be observational

%% Diagnose, don't gatekeep: name every missing export in the error.
-spec verify_signature(module()) -> ok.
verify_signature(Mod) ->
    case code:ensure_loaded(Mod) of
        {module, Mod} -> ok;
        {error, Why} -> error({signature_violation, Mod, {not_loadable, Why}})
    end,
    Required = [{empty, 0}, {fill, 1}, {overlay, 2}, {rasterize, 1}, {eql, 2}],
    case [FA || {F, A} = FA <- Required,
                not erlang:function_exported(Mod, F, A)] of
        []      -> ok;
        Missing -> error({signature_violation, Mod, {missing_exports, Missing}})
    end.

%%% ==========================================================================
%%% PART 2: THE SEMANTIC DOMAIN (shared denotation)
%%% ==========================================================================

-spec blank() -> raster().
blank() -> #{}.

-spec uniform(pixel()) -> raster().
uniform(Px) ->
    maps:from_list([{{X, Y}, Px} || X <- lists:seq(0, ?GRID_W - 1),
                                    Y <- lists:seq(0, ?GRID_H - 1)]).

%% Top-wins-if-painted: keys of Top override keys of Bottom.
-spec over(raster(), raster()) -> raster().
over(Top, Bottom) -> maps:merge(Bottom, Top).

-spec raster_eql(raster(), raster()) -> boolean().
raster_eql(A, B) -> A =:= B.

%%% ==========================================================================
%%% PART 4: LAWS — generator + property suites, generic over Mod
%%% (Part 3, the encodings, live in canvas_initial.erl / canvas_final.erl —
%%%  and any other module honouring the behaviour, e.g. a process-based one.)
%%% ==========================================================================

%% Deterministic, purely-threaded PRNG state (rand:*_s) so identically-seeded
%% twin states build identical term shapes across different implementations.
gen_pixel(S0) ->
    {R, S1} = rand:uniform_s(256, S0),
    {G, S2} = rand:uniform_s(256, S1),
    {B, S3} = rand:uniform_s(256, S2),
    {{R - 1, G - 1, B - 1}, S3}.

%% Terms come from the implementation's OWN constructors: well-typed by
%% construction. Leaves only at the depth bound (structural termination).
-spec gen_canvas(module(), non_neg_integer(), rand:state()) ->
          {term(), rand:state()}.
gen_canvas(Mod, 0, S0) ->
    case rand:uniform_s(2, S0) of
        {1, S1} -> {Mod:empty(), S1};
        {2, S1} -> {Px, S2} = gen_pixel(S1), {Mod:fill(Px), S2}
    end;
gen_canvas(Mod, Depth, S0) ->
    case rand:uniform_s(3, S0) of
        {1, S1} -> {Mod:empty(), S1};
        {2, S1} -> {Px, S2} = gen_pixel(S1), {Mod:fill(Px), S2};
        {3, S1} ->
            {T, S2} = gen_canvas(Mod, Depth - 1, S1),
            {B, S3} = gen_canvas(Mod, Depth - 1, S2),
            {Mod:overlay(T, B), S3}
    end.

defaults(Cfg) ->
    maps:merge(#{iterations => 200, max_depth => 5, seed => 16#ADD0CAFE}, Cfg).

seed_state(Seed) -> rand:seed_s(exsss, {Seed, Seed, Seed}).

expect_law(true, _Name, _Cfg, _Iter) -> ok;
expect_law(false, Name, #{seed := Seed, max_depth := D}, Iter) ->
    io:format("LAW FAILED: ~s (seed=~.16B, iteration=~b, depth=~b)~n",
              [Name, Seed, Iter, D]),
    error({law_failed, Name, #{seed => Seed, iteration => Iter}}).

%% Monoid identity + associativity + idempotence for (Canvas, overlay, empty),
%% every assertion observational. Red here against the INITIAL encoding means
%% the laws/domain are wrong; against the final encoding only, the impl is.
-spec verify_monoid_laws(module(), law_config()) -> ok.
verify_monoid_laws(Mod, Cfg0) ->
    ok = verify_signature(Mod),
    Cfg = #{iterations := N, max_depth := D, seed := Seed} = defaults(Cfg0),
    lists:foldl(
      fun(I, S0) ->
              {X, S1} = gen_canvas(Mod, D, S0),
              {Y, S2} = gen_canvas(Mod, D, S1),
              {Z, S3} = gen_canvas(Mod, D, S2),
              E = Mod:empty(),
              expect_law(Mod:eql(Mod:overlay(E, X), X), "left identity",  Cfg, I),
              expect_law(Mod:eql(Mod:overlay(X, E), X), "right identity", Cfg, I),
              LHS = Mod:overlay(Mod:overlay(X, Y), Z),
              RHS = Mod:overlay(X, Mod:overlay(Y, Z)),
              expect_law(Mod:eql(LHS, RHS),             "associativity",  Cfg, I),
              expect_law(Mod:eql(Mod:overlay(X, X), X), "idempotence",    Cfg, I),
              S3
      end,
      seed_state(Seed),
      lists:seq(1, N)),
    ok.

%% The ADD keystone: two implementations denote the same algebra. Twin
%% identically-seeded generators build the same term shape through each
%% module's constructors; their rasters must agree exactly.
-spec verify_homomorphism(module(), module(), law_config()) -> ok.
verify_homomorphism(ModA, ModB, Cfg0) ->
    ok = verify_signature(ModA),
    ok = verify_signature(ModB),
    #{iterations := N, max_depth := D, seed := Seed} = defaults(Cfg0),
    lists:foldl(
      fun(_I, {SA0, SB0}) ->
              {TA, SA1} = gen_canvas(ModA, D, SA0),
              {TB, SB1} = gen_canvas(ModB, D, SB0),
              true = raster_eql(ModA:rasterize(TA), ModB:rasterize(TB)),
              {SA1, SB1}
      end,
      {seed_state(Seed), seed_state(Seed)},
      lists:seq(1, N)),
    ok.

%%% ==========================================================================
%%% Verification suite (eunit)
%%% ==========================================================================

initial_laws_test_() ->
    {timeout, 60,
     fun() -> ok = verify_monoid_laws(canvas_initial, #{}) end}.

final_laws_test_() ->
    {timeout, 60,
     fun() -> ok = verify_monoid_laws(canvas_final, #{}) end}.

homomorphism_test_() ->
    {timeout, 60,
     fun() -> ok = verify_homomorphism(canvas_initial, canvas_final, #{}) end}.

doctrine_guard_structural_vs_observational_test() ->
    X = canvas_initial:fill({1, 2, 3}),
    Wrapped = canvas_initial:overlay(canvas_initial:empty(), X),
    %% Structurally different terms...
    ?assertNotEqual(Wrapped, X),
    %% ...observationally equal — exactly what the identity law asserts.
    ?assert(canvas_initial:eql(Wrapped, X)).

broken_module_is_diagnosed_test() ->
    ?assertError({signature_violation, lists, {missing_exports, _}},
                 verify_signature(lists)).
