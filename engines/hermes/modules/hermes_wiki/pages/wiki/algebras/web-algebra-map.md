---
id: hermes-imported-web-algebra-map
status: published
type: reference
generated: false
allow_example_links: true
migrated_from: zigvm/docs/design/WEB_ALGEBRA_MAP.md
---
# The web-stack algebra map — Phoenix and Eliom, read algebraically

The comparison documents (`docs/bonsai/PHOENIX_COMPARISON.md`,
`OCSIGEN_COMPARISON.md`, `FRONTEND_LIVEVIEW_COMPARISON.md`,
`PHOENIX_DREAM_MAP.md`) established *what* Phoenix and Eliom provide. This
document asks a different question: **what algebraic structure is each of those
capabilities, and what is its typed implementation in Dream plus Bonsai?**

The value of the question is that a capability copied feature-by-feature
arrives as a pile of conventions, whereas a capability identified as a monoid,
an applicative or a lattice arrives with its laws attached — and the laws are
the part that survives a refactor.

---

## 1 · The map at a glance

| Capability | Structure | Phoenix | Eliom | Typed form here |
|---|---|---|---|---|
| Routing | Injective partial map, first-match choice | Compiled dispatch, verified paths | Service value **is** the URL | **`Route_algebra`** — landed |
| Link construction | Free monoid over segments; encoding is a homomorphism | Verified `~p` sigil | Derived from the service | **`Route_algebra.to_path`** — landed |
| Middleware | **Monoid** with short-circuit; the error monad | Plug pipeline | No per-route combinator | **`Middleware_algebra`** — landed |
| Parameter validation | **Applicative** with error accumulation | Ecto changeset | Combinator-typed params | **`Validated`** — landed |
| Markup | Free monoid over nodes, constrained by a typed grammar | HEEx, compile-checked | TyXML | **`Typed_html`** — landed |
| Session scope | **Lattice** | Cookie store | group ⊃ session ⊃ tab | **`Scope_lattice`** — landed |
| Server push | Topic **semilattice**, delivery a monoid action | PubSub and Channels | Comet only, no WebSockets | **`Channel_envelope`** + **`Resync`** — wired over WebSocket + Zenoh, gap-detected |
| UI composition | **Applicative** functor over incremental values | LiveView diffing | React signals | Bonsai — already applicative |
| UI state | **Monoid action** on a model | `handle_event` | Eliom references | `apply_action` — already this shape |
| Wiki and ZK links | Same shape as routing, different address space | not applicable | not applicable | **`Note_ref`** — landed |

"Landed" means implemented with executable laws in the gate. "Proposed" means
the structure is identified and the laws are written below, but the code is not
yet there — stated explicitly so this table cannot be misread as a status
report.

---

## 2 · Routing is an injective partial map

**The structure.** A router is a partial function from targets to handlers,
`Target ⇀ Handler`, assembled by a *left-biased choice* operator: try the first
pattern, else the next. Left-biased choice is associative with an identity
(the never-matching route), so the router is a **monoid** — but a monoid whose
operation is not commutative, which is exactly why route order is load-bearing
and why shadowing is a real defect rather than a style issue.

Adding **injectivity** — distinct routes have distinct addresses — makes order
irrelevant to the *meaning* of the table, and that is what turns a pile of
patterns into an algebra.

**Phoenix** compiles the table into a dispatch function and verifies link paths
at compile time through the `~p` sigil. **Eliom** goes further: the service
value *is* the URL, so links and forms are constructed from the same value the
server registered, and there is no reverse-routing table at all.

**Here.** `Route_algebra` takes Eliom's idea without Eliom. The route is a
closed variant; `to_path` is the only way to obtain a URL; `pattern` derives
the router's view from the same value; `ORACLE≡FINAL` catches shadowing;
`COVERAGE` reads the live Dream router's source and fails if the algebra has
drifted from it. Full treatment in `ROUTE_ALGEBRA.md`.

---

## 3 · A middleware pipeline is a monoid with short-circuit

**The structure.** A plug is `Conn -> Conn`; a pipeline is composition;
composition is associative; the identity plug is a unit. That is a monoid, and
it is why plugs compose so cleanly.

The interesting part is `halt`. A halted connection short-circuits the rest of
the pipeline, which makes the real carrier `Conn + Halted` — the **error
monad** shape, with `halt` as the left-absorbing element. The law that matters
follows directly:

```text
LAW HALT-ABSORBS      halt(c) >>= f  =  halt(c)          for every f
LAW REJECT-HALTS      a stage that rejects a request MUST halt
```

The second is the one that catches real bugs: an authentication plug that sets
a status but forgets to halt lets the request continue to the handler, which is
a security defect rather than a routing one.

**Dream** already has this — middleware is ordinary function composition,
`handler -> handler`, and it is a monoid without anyone having to say so. What
is missing is the *law*: nothing checks that a rejecting stage halts.

**Here.** `Middleware_algebra` implements the structure over an explicit
`Outcome = Continue | Halted`, with `reject` as the **only** way to set a
rejecting status — and it halts in the same expression, so REJECT-HALTS holds
by construction for every stage built through the module. The law still exists,
to catch a stage built some other way.

Two encodings: an `ORACLE` that walks the pipeline testing the flag at each
step, and a `FINAL` `mconcat` that folds the whole pipeline into one stage
before it sees a connection. Held equal over 585 pipelines × 6 connections.

Three details worth noting because they are where the value is:

- Dispatch is on the **typed route**, not a path string, so `when_route` cannot
  be given a typo.
- `WITNESS NON-COMMUTATIVE` is stated as a law. Assuming commutativity is how
  an auth stage ends up after the handler it protects, and if that witness ever
  starts passing, the corpus has stopped distinguishing order.
- `AUDIT-ORDER` pins the dynamic behaviour: the trace is the stage order,
  truncated exactly at the halt.

**Wired.** `site_pipeline.ml` declares the production stages as pure values —
security headers, an invalid-query guard, an unknown-API-route guard, tracing —
and `dream_web.ml` is the single interpretation of them into Dream middleware.
Because the stage list is pure, the law corpus *contains the production
stages*, so the monoid laws quantify over the pipeline the server really runs
rather than over test fixtures.

The route algebra is now **load-bearing at runtime**: an API path it does not
name is rejected before the router sees it. That is only safe because
`COVERAGE-SERVED` proves the algebra names every served pattern, and the gate
fails if that stops being true. The guard is bounded to the `/api/` prefix on
purpose — static assets, the bundle and verbs the algebra does not model live
outside it, and rejecting those would enforce a completeness claim the algebra
does not make.

**A finding that only running it produced.** With the guard wired,
`?format=grapml` returned **404**. The path exists; the query is wrong; 404 was
the wrong answer. `parse` had collapsed "unknown path" and "rejected query"
into a single `None`. `Route_algebra.classify` now separates them —
`Matched | Bad_query | No_route` — derived from the oracle table rather than
restated, and a `400` stage answers the distinction ahead of the `404` one.
Reading the code would not have shown this.

---

## 4 · Parameter validation is an applicative, not a monad

**The structure.** This is the most commonly mis-implemented one, and the
distinction is not academic. Validating a form should report **every** invalid
field, not the first. A monad sequences — `bind` needs the previous value, so
the first failure stops everything. An **applicative** combines independent
computations, so failures can accumulate:

```text
LAW ACCUMULATION      (Error e1) <*> (Error e2)  =  Error (e1 ⊕ e2)
```

where `⊕` is the errors' own monoid. Ecto's changeset is exactly this: it
collects per-field errors rather than aborting. Eliom's parameter combinators
are typed but reject on the first mismatch.

**Here.** `Validated` implements the applicative, and keeps the monadic
alternative alongside it *deliberately* — not to use, but so a law can
demonstrate what it costs. `both_monadic` satisfies identity, homomorphism,
interchange and composition; it fails ACCUMULATION alone, dropping the second
field's error. `WITNESS MONAD-LOSES` asserts exactly that, which turns "use an
applicative here" from a preference into a checked fact.

The distinction is sharper than "applicative good, monad bad", and one more law
pins it. Within a **single** field, sequencing is legitimately monadic:
`bounded` needs the *parsed* integer, a real data dependency, so a weight of
`"x"` reports one error and not two. Between **independent** fields, sequencing
would be a defect. `LAW FIELD-DEPENDENCY` holds that line.

`LAW CROSS-ALGEBRA` joins the two algebras: a value admitted by `id_field` is
one `Route_algebra` will render into a URL, because both consult the same
`Id.of_string`. Validation cannot admit an identifier routing would refuse —
so a form that passes cannot produce a link that fails.

**Wired, and it removed a real defect.** The graph handlers read `max_nodes`
through `bounded_int`, which clamped inside a `try ... with _ -> default`: a
request for `?max_nodes=lots` returned a **200** carrying a different graph
than the caller asked for, with nothing to indicate the parameter had been
ignored. `Dream_web.bounded_query` distinguishes ABSENT (use the default) from
MALFORMED (report it), and the response now names the field:

```json
{"error":"invalid_parameters",
 "detail":"max_nodes must be between 25 and 1500",
 "fields":[{"field":"max_nodes","message":"must be between 25 and 1500"}]}
```

`bounded_int` was **deleted** rather than deprecated. Leaving it in place would
have left a working escape hatch beside the rule forbidding it.

---

## 5 · Markup is a free monoid constrained by a typed grammar

**The structure.** A node list is a free monoid under concatenation. HTML's
content model then constrains which lists are legal in which position — a
typed grammar layered over the free monoid. TyXML encodes that grammar in
OCaml's type system directly, which is why `<b>` inside `<title>` does not
lint-fail: it does not compile.

**Phoenix** achieves a similar effect differently, verifying HEEx templates at
compile time. **Eliom** uses TyXML itself.

**Here.** `Typed_html` wraps TyXML and composes it with the route algebra. The
composition is the point, and neither library provides it alone:

- TyXML types the markup, and has nothing to say about whether an `href` points
  anywhere.
- `Route_algebra` types the address, and has nothing to say about where the
  address is placed.
- An anchor constructor that accepts a **route** and never a string makes a
  broken link a compile error.

This sits alongside `HTML_ALGEBRA.md` rather than replacing it, and the split
follows the provenance standard the lint programme already established:

| Provenance | Instrument | Standard |
|---|---|---|
| Authored document | `Doc_lint` after the fact | What a renderer does with it |
| Generated artifact | `Typed_html` at construction | Malformed markup is unconstructible |

A generated page is additionally fed back through the project's own lint
registry as a **dogfood law**: if the markup we emit could not pass our own
linter, one of the two is wrong.

---

## 6 · Session scope is a lattice

**The structure.** Eliom's scopes — group ⊃ session ⊃ client process — form a
**lattice** under containment, and its state cells are indexed by a point in
that lattice. The laws are the lattice laws plus monotonicity:

```text
LAW CONTAINMENT       a value at a wider scope is visible at every narrower one
LAW ISOLATION         a value at a narrower scope is invisible to its siblings
```

Eliom's is the richest of the three frameworks; Phoenix has a cookie store;
Dream has three backends and no scope structure.

**Here.** The harness UI is a single-operator read-only dashboard over a
private network, so session scoping is close to vacuous today. It is recorded
because the *shape* becomes relevant the moment more than one viewer exists,
and because a lattice retrofitted later is a rewrite.

---

## 7 · Server push is a topic semilattice with a monoid action

**The structure.** Subscriptions form a **join-semilattice** — subscribing to
more topics only widens what you receive, and joining two subscription sets is
their union. Delivery is a **monoid action** of the event sequence on client
state: applying events in order is associative, and the empty sequence is the
identity.

That last property is what makes **sequence numbers** the right primitive:

```text
LAW GAP-DETECTION     a consumer can decide, from the envelope alone, whether
                      it missed an event
LAW DEGRADE           on a gap, re-read the authoritative source — never guess
                      what the missing event was
```

**Phoenix** has this natively. **Eliom** has Comet long polling and **no
WebSockets**, which is precisely why adopting Eliom would have cost us the
capability we set out to gain. **Dream** has the WebSocket transport; what is
missing is the topic layer above it.

**Here.** `Channel_envelope` carries Phoenix's five-slot envelope over both
transports, and `resync.ml` is the JOIN that makes server-held rendering safe:
the sequence rides in the Channels `ref`, and a consumer decides apply /
ignore-replay / resync from one integer of state.

The hazard it removes is specific. A slot-keyed diff cannot notice a gap on
its own, because it applies PERFECTLY WELL to the wrong base view — so a
client that misses one update diverges silently and permanently, every later
diff being computed against a state it no longer has. `LAW
NO-SILENT-DIVERGENCE` quantifies over every single-fault mutation of a real
stream (drop, duplicate, reorder) and requires that the client either MATCHES
the server or KNOWS it is stale.

The tail case is disclosed and closed rather than hidden: a gap is noticed by
seeing a LATER update, so a dropped FINAL update is invisible to the stream
alone. The heartbeat carries the server's sequence, which catches it — and
`LAW TAIL-GAP` asserts BOTH halves, so neither the residual nor its mitigation
can be quietly lost.

---

## 8 · The UI layer: applicative, and a monoid action

**The structure.** Bonsai's `Value.t` is an **applicative** functor and
deliberately not a monad — there is no `bind`, because a computation whose
*shape* depends on its input cannot have a stable incremental graph. LiveView
reaches the same destination by a different route: the server holds state and
ships diffs, so the shape is free to vary but every change costs a round trip.

State transitions are a **monoid action**: `apply_action : model -> action ->
model`, where action sequences compose associatively and the empty sequence is
the identity. Both Bonsai and LiveView have this shape; naming it is what makes
the transition function worth property-testing.

The highest-value laws for our own components, in order:

```text
LAW ACTION-ASSOC      applying (a then b) equals applying a, then applying b
LAW IDENTITY          the empty action sequence leaves the model unchanged
LAW IDEMPOTENCE       for the actions that claim it — set, toggle-to-state
```

---

## 9 · Wiki and ZK links are routing over a different address space

The user requirement covers the wiki and ZK surfaces, and the pleasant result
is that **they need no new algebra**. A `[[note-name]]` link is an address; the
note set is the address space; resolution is a partial function; and the
integrity property is the one already written:

```text
LAW LINK-COVERAGE     every [[link]] resolves to a note that exists
```

which is the exact shape of `COVERAGE-SERVED` for HTTP routes. The typed form
is a `Note_ref.t` abstract identifier with a partial `of_string`, a total
resolver returning an option, and the coverage law over the whole corpus.

This is the fractal claim doing real work rather than decorating a document:
the same structure appears at the HTTP boundary, in the wiki, and in the ZK
graph, so one algebra and one law family covers all three.

---

## 10 · What this map is not

- It is a structural reading of two frameworks, not a benchmark. Nothing here
  measures performance.
- Phoenix and Eliom were assessed from documentation and their own source;
  Eliom is **not installed here** and was not executed.
- Everything in the table is landed. Routing, middleware, validation and the
  push path are WIRED into the running server; the scope lattice is
  anticipatory (nothing consults it yet) and `Typed_html` is so far used only
  by the route-index page. Those two are stated so the table is not read as
  more than it is.
- Identifying a structure does not by itself buy anything. The purchase happens
  when the laws are executable in the gate, which is true today for routing,
  markup and the push event, and not yet true for the rest.
