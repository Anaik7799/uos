# BEAM mechanics for algebraic code

The Haskell→BEAM translation table, then the load-bearing patterns with exact
code. Bundled examples verified on OTP 25; everything targets OTP 24+.
Elixir mappings in §7.

## Contents
1. Translation table
2. Signatures: behaviours + runtime contract (+ dialyzer)
3. Tagged-tuple initial encodings
4. Property-based testing (threaded rand state, seeds, shrinking, PropEr)
5. Processes, gen_servers, and distribution as interpretations
6. Deriving efficient final encodings on the BEAM
7. Elixir mapping
8. Toolchain, versions, performance

## 1. Translation table

| Book concept (Haskell) | BEAM idiom | Notes |
|---|---|---|
| Typeclass / signature | Behaviour (`-callback`) + `verify_signature(Mod)` | Compiler warns; the runtime check *fails loudly with names* |
| Typeclass instance | Module implementing the behaviour | Law suites take `Mod` and call `Mod:op(...)` |
| Alternative: first-class instance | Map of funs `#{empty := fun .../0, ...}` | Use when instances must be built at runtime; behaviours otherwise |
| GADT / initial encoding | Tagged tuples + `-type` union | `empty \| {fill, Px} \| {overlay, T, B}` |
| Final/tagless encoding | The denotation term itself | Often literally a map |
| Manual memory / arenas | Nothing — immutable terms + GC | Whole doctrine section deleted vs. systems languages |
| QuickCheck `Arbitrary` | `gen_x(Mod, Depth, RandState)` threading `rand:*_s` | Or PropEr generators (§4) |
| QuickCheck property | eunit `_test_()` looping the law over generated terms | Or `?FORALL` in PropEr |
| `===` up to observation | `Mod:eql/2` comparing denotations | Doctrine rule 1 |
| — (no equivalent) | Process/gen_server/distributed interpretation | §5 — BEAM-unique |

Immutability is the quiet superpower: no aliasing means no law can be broken
behind your back, and sharing subterms between generated test cases is free.

## 2. Signatures: behaviours + runtime contract

Behaviour module declares the shape; `verify_signature/1` enforces it with a
diagnosable error (compiler behaviour warnings are advisory and easily lost in
CI noise — the runtime check is the hard gate, called first by every law
suite):

```erlang
-callback empty() -> term().
-callback fill(pixel()) -> term().
-callback overlay(Top :: term(), Bottom :: term()) -> term().
-callback rasterize(term()) -> raster().    %% the observation [[.]]
-callback eql(term(), term()) -> boolean(). %% MUST be observational

verify_signature(Mod) ->
    case code:ensure_loaded(Mod) of
        {module, Mod} -> ok;
        {error, Why} -> error({signature_violation, Mod, {not_loadable, Why}})
    end,
    Required = [{empty,0},{fill,1},{overlay,2},{rasterize,1},{eql,2}],
    case [FA || {F,A}=FA <- Required,
                not erlang:function_exported(Mod, F, A)] of
        []      -> ok;
        Missing -> error({signature_violation, Mod, {missing_exports, Missing}})
    end.
```

`-callback` cannot express per-implementation opaque types, hence `term()`;
recover precision inside each implementation with `-type canvas() :: ...`,
`-export_type`, and `-spec`s on every export, then run dialyzer. The negative
test belongs in the suite:

```erlang
broken_module_is_diagnosed_test() ->
    ?assertError({signature_violation, lists, {missing_exports, _}},
                 verify_signature(lists)).
```

## 3. Tagged-tuple initial encodings

```erlang
-type canvas() :: empty
                | {fill, canvas_algebra:pixel()}
                | {overlay, canvas(), canvas()}.

empty() -> empty.
fill(Px) -> {fill, Px}.
overlay(Top, Bottom) -> {overlay, Top, Bottom}.

%% Interpreter clauses ARE the [[.]] equations — exhaustive, NO catch-all.
rasterize(empty)           -> canvas_algebra:blank();
rasterize({fill, Px})      -> canvas_algebra:uniform(Px);
rasterize({overlay, T, B}) -> canvas_algebra:over(rasterize(T), rasterize(B)).

eql(A, B) -> canvas_algebra:raster_eql(rasterize(A), rasterize(B)).
```

No catch-all is doctrine rule 4: an unhandled new variant crashes with
`function_clause` (let it crash) and dialyzer's success typing flags the gap
statically. Atoms for nullary constructors, tagged tuples otherwise; records
buy nothing here and cost header coupling. Deep user-supplied terms: the
recursive interpreter is fine to ~hundreds of thousands of nodes (BEAM stacks
grow); convert to an explicit stack only if profiling says so.

## 4. Property-based testing

**Dependency-free generator** — thread explicit `rand` state (`*_s`
functions) so generation is pure and reproducible; terms come from the
implementation's own constructors:

```erlang
gen_canvas(Mod, 0, S0) ->
    case rand:uniform_s(2, S0) of                 %% leaves only at the bound
        {1, S1} -> {Mod:empty(), S1};
        {2, S1} -> {Px, S2} = gen_pixel(S1), {Mod:fill(Px), S2}
    end;
gen_canvas(Mod, Depth, S0) ->
    case rand:uniform_s(3, S0) of
        {1, S1} -> {Mod:empty(), S1};
        {2, S1} -> {Px, S2} = gen_pixel(S1), {Mod:fill(Px), S2};
        {3, S1} -> {T, S2} = gen_canvas(Mod, Depth-1, S1),
                   {B, S3} = gen_canvas(Mod, Depth-1, S2),
                   {Mod:overlay(T, B), S3}
    end.
```

Seeding: `rand:seed_s(exsss, {Seed, Seed, Seed})` with a fixed default
(`16#ADD0CAFE`); echo seed + iteration + depth on failure so any red run is
reproducible. Generator quality: every variant reachable; recursion always
shrinks `Depth`; payloads span the full range (`rand:uniform_s(256, S)`, not
three constants); weight leaves up if interesting small terms drown.

**Law suite** — one generic function per structure, laws transcribed 1:1,
`lists:foldl` threading the PRNG state; eunit wrappers with timeouts:

```erlang
initial_laws_test_() ->
    {timeout, 60, fun() -> ok = verify_monoid_laws(canvas_initial, #{}) end}.
```

**Shrinking** — hand-rolled generators don't shrink; approximate honestly: on
failure, rerun the same seed at `max_depth = 0, 1, 2, ...` and report the
smallest failing depth, printing both denotations.

**PropEr / StreamData** — when the project already has them, prefer them:
real shrinking for free. The mapping is mechanical:

```erlang
%% PropEr: same recursive shape via ?LAZY/?SIZED, laws as ?FORALL
prop_left_identity(Mod) ->
    ?FORALL(X, canvas_gen(Mod),
            Mod:eql(Mod:overlay(Mod:empty(), X), X)).
```

Keep the bundled hand-rolled suite regardless — it runs anywhere with zero
deps, and the twin-seed homomorphism trick (below) needs deterministic paired
generation that shrinking libraries don't naturally give you.

**Twin-seed homomorphism** — two states from one seed make identical choices,
so the same term *shape* is built through two different modules:

```erlang
S = rand:seed_s(exsss, {Seed, Seed, Seed}),
lists:foldl(fun(_, {SA0, SB0}) ->
    {TA, SA1} = gen_canvas(ModA, D, SA0),
    {TB, SB1} = gen_canvas(ModB, D, SB0),
    true = raster_eql(ModA:rasterize(TA), ModB:rasterize(TB)),
    {SA1, SB1}
end, {S, S}, lists:seq(1, N)).
```

Sound only while there is exactly **one** generator generic over `Mod` — never
write per-encoding generators.

## 5. Processes, gen_servers, distribution — interpretations

The BEAM-unique move: a process boundary is just another interpretation, and
the *same* law suite must pass through it. Minimal pattern — terms are pids,
each holding its denotation:

```erlang
-module(canvas_process).
-behaviour(canvas_algebra).
%% empty/fill spawn a process holding the raster; overlay asks children and
%% spawns the merge; rasterize/eql are synchronous asks. Same suite, no edits.
```

What this buys, concretely:

- **Protocol design**: a gen_server's API *is* an algebra; its message
  protocol is the signature, `handle_call` clauses are the interpreter, and
  the pure final encoding is the oracle the server is property-tested against.
  Design the algebra first, wrap the server around the final encoding, keep
  the state pure inside.
- **CRDT-shaped laws**: assoc + comm + idem (a semilattice, see the catalog)
  is exactly the merge contract for convergent replicated state — if the law
  suite is green, replicas may merge in any order/duplication and converge.
- **Hot code upgrades**: laws are the behavioral contract a new module version
  must preserve; run the homomorphism test between old and new modules before
  shipping the upgrade.
- **Supervision**: because denotations are pure terms, a crashed interpreter
  process loses nothing that can't be re-derived — restart strategies stay
  trivial.

Rules: effects stay in the interpretation module (doctrine rule 3); law
suites over process interpretations use fewer iterations (spawning thousands
of procs is cheap but not free) and synchronous asks with timeouts.

## 6. Deriving efficient final encodings on the BEAM

- Function-like denotation over a small finite domain → **a map** — and often
  the combinator is a stdlib map op (canvas `overlay` *is*
  `maps:merge(Bottom, Top)`). Map `=:=` is canonical: order-independent,
  so observational equality on the final encoding is free.
- Laws admitting normal forms → store the normal form: assoc+identity ⇒ flat
  list; +comm+idem ⇒ `ordsets`/`gb_sets`; annihilator ⇒ short-circuit in the
  interpreter.
- Fold-like denotation → store the accumulator (counters, monoidal metrics —
  aggregate across processes soundly because associativity says chunking is
  irrelevant).
- Each optimization cites the licensing law in a comment; the homomorphism
  test against the initial encoding stays in the suite forever.

## 7. Elixir mapping

Identical doctrine, different spelling: `@callback`/`@behaviour` for the
signature; `defguard`/pattern-matched `def` clauses for interpreters (still no
catch-all over domain variants); structs or tagged tuples for the initial
encoding; **StreamData + ExUnit properties** for laws
(`check all x <- canvas_gen(impl)`); `Map.merge/2` semantics match `maps:merge`
(right wins — mind the argument order in `over/2`); typespecs + dialyzer
unchanged. The Erlang modules in this skill are callable from Elixir directly
(`:canvas_algebra.verify_monoid_laws(MyImpl, %{})`) — implement the behaviour
in Elixir and reuse the suite as-is.

## 8. Toolchain, versions, performance

- Compile+test anywhere: `scripts/run_beam_tests.sh <files...>` (two-pass
  `erlc` so behaviour declarations resolve, then eunit verbose). Debian/Ubuntu
  toolchain: `apt-get install -y erlang-base erlang-eunit erlang-dev`.
- Report `erlang:system_info(otp_release)` with delivered code. Bundled code
  needs only OTP 24+ (`rand` exsss OTP 21+, map syntax OTP 17+); current
  upstream is OTP 28.x — nothing here touches deprecated surface, but always
  compile on the user's release.
- Performance: tagged-tuple dispatch is a single-word match; maps of ≤32 keys
  are flatmaps (cheap merge/compare); the initial encoding is the oracle, not
  the product — production paths call the final encoding, the AST lives in
  tests. Large generated suites: prefer `lists:foldl` over building term
  lists; per-iteration terms are garbage-collected as they drop.
