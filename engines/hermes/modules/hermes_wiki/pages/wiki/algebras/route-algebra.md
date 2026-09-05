---
id: hermes-imported-route-algebra
status: published
type: reference
generated: false
migrated_from: zigvm/docs/design/ROUTE_ALGEBRA.md
---
# The Route Algebra — paths, URLs and routes as typed values

The third algebra in this series, after `TABLE_ALGEBRA.md` and
`HTML_ALGEBRA.md`, and the first one that governs *structure the system emits*
rather than *documents the system reads*.

Implementation: `harness/route_algebra.ml`. Laws: `harness/route_laws.ml`,
executed by `harness/test_route_algebra.exe` and by the harness's
`--verify-formal` stage — the same code, so the gate and the developer loop
cannot disagree about what the specification says.

---

## 1 · The defect this removes

Before this algebra, every address in the system existed as a string in two
unrelated places:

```ocaml
(* server *)  Dream.get "/api/v1/projects/:id" (fun r -> ... Dream.param r "id" ...)
(* client *)  Workspace_client.patch_json ~url:("/api/v1/projects/" ^ project.id)
```

Nothing connects them. Rename the route and the compiler says nothing; the
failure surfaces as a 404 in a browser, possibly only on the one path a human
happens to click. The captured parameter arrives as `string` even where the
handler immediately parses it as an integer, so the type that would have caught
a malformed link is discarded at the door.

Measured at the time of writing: **30 route patterns** on the server and
**20 URL literals** in the Bonsai client, with no mechanical relationship
between the two sets.

The fix is the one idea worth taking from Eliom, and it requires none of Eliom:
**make the route a value.** The URL is derived from that value by a total
function; the router pattern is derived from the same value; and no other way
to produce either exists. A link that does not correspond to a route is then
not a 404 — it is a type error.

---

## 2 · Ontology

| Term | Definition |
|---|---|
| **Segment** | An atomic path component. Either a `Literal` or a `Capture`. |
| **Path** | A finite sequence of segments. |
| **Method** | The HTTP verb. Part of a route's identity, not a decoration. |
| **Capture** | A typed hole in a path; its type is the parameter's real type. |
| **Query** | Typed optional parameters, drawn from closed variants. |
| **Route** | A typed value denoting exactly one endpoint. |
| **Target** | A concrete request: method, decoded segments, query. |
| **Pattern** | The router's view of a route, with captures named. |
| **Link** | A rendered URL. Obtainable only from a route. |

The ontology is deliberately small. Everything a web framework calls "routing"
decomposes into these nine terms, and each one is a type in the implementation
rather than a convention in a comment.

---

## 3 · Semantic domain

A route denotes a target:

```text
⟦·⟧ : Route → Target        Target = Method × Segment* × Query
```

and the parser is the intended inverse:

```text
parse : Target → Route option
```

`Segment*` holds **decoded** strings. Percent-encoding is a property of the
*rendered path*, not of the target, so the two concerns cannot be confused —
which is where the classic encode/decode asymmetry defect lives.

---

## 4 · Signature

```ocaml
module Id : sig
  type t
  val of_string : string -> t option   (* PARTIAL — the caller must handle it *)
  val to_string : t -> string
end

type meth = GET | POST | PUT | PATCH | DELETE | HEAD
type export_format = Json | Graphml | Dot
type t = Root | Health | ... | Project of Id.t | ...
type target = { meth : meth; segments : string list; query : (string * string) list }

val denote     : t -> target             (* TOTAL *)
val to_path    : t -> string             (* TOTAL — the only way to get a URL *)
val pattern    : t -> string             (* the router's view *)
val of_target  : target -> t option      (* TOTAL, FINAL encoding *)
val of_target_oracle : target -> t option (* TOTAL, ORACLE encoding *)
val parse      : meth:string -> path:string -> t option  (* TOTAL over bytes *)
val all        : t list                  (* the totality witness *)
```

`Id` is abstract, and that is the load-bearing design decision. The only way to
obtain one is `of_string`, which is partial, so a caller **must confront the
invalid case at compile time**. This is what makes `to_path` total: it cannot
be handed a value that would produce a malformed URL, because that value cannot
be constructed.

`Id.of_string` rejects the empty string (collapses a segment), `/` (forges a
segment boundary), control characters (header-splitting shapes), and `.` / `..`
(traversal). Everything else — spaces, `%`, `?`, `#`, non-ASCII — is admitted
and carried safely through percent-encoding, because refusing legitimate input
is a defect too.

---

## 5 · Two encodings

| Encoding | How | Why it exists |
|---|---|---|
| **ORACLE** | Linear scan over a pattern table; each row is a method, a pattern, and a builder | Obviously correct — a row has nothing to get wrong. `O(routes × segments)`. |
| **FINAL** | Direct OCaml pattern match on method and segment list | Fast, and the encoding where a subtle mistake hides: a misordered branch silently shadows a later route. |

The `ORACLE≡FINAL` law is what makes the fast encoding safe to ship, and it is
not decoration. **A shadowing bug is invisible to every other law here** —
round-trip passes, injectivity passes, canonicity passes, and one route is
quietly unreachable.

---

## 6 · Laws

Static laws — properties of the algebra:

| Law | Statement |
|---|---|
| **TOTALITY-OF-WITNESSES** | `all` contains exactly one witness per constructor. Makes every other law a quantification over the route *type*, not over a sample. |
| **ROUND-TRIP** | `of_target (denote r) = Some r`, for every route. |
| **ROUND-TRIP-URL** | `parse (to_path r) = Some r`, through the wire form an actual request takes. |
| **ORACLE-FINAL** | The two encodings agree, on every witness and on 4000 generated targets. |
| **INJECTIVITY** | Distinct routes have distinct addresses. Two routes at one address means one is unreachable, and which one depends on declaration order. |
| **CANONICITY** | A rendered path is already normal form: rooted, no empty segment, no `.` or `..`, no trailing slash except at the root. |
| **PATTERN-AGREEMENT** | `pattern r` and `to_path r` agree on arity, and literal segments are literally equal. This is what makes generating the router from the route value safe. |

Dynamic laws — properties of the running matcher:

| Law | Statement |
|---|---|
| **NO-SHADOWING** | A route's own URL parses back to that route, across 21 identifier shapes. The dynamic counterpart of injectivity: it tests the matcher, not the renderer. |
| **ENCODING** | The captured identifier survives rendering and parsing unchanged. |
| **TOTALITY** | The parser never raises, over 5000 adversarial requests. It reads bytes from a peer we do not control; a decoder that raises turns a hostile client into a harness crash. |
| **QUERY-TYPED** | An admitted format parses to its variant; an unrecognised one is **rejected, not silently defaulted**. A silent default is how `?format=grapml` quietly returns JSON and the caller believes it received GraphML. |

Integrity laws — the algebra against reality:

| Law | Statement |
|---|---|
| **DISPATCH-COMPLETE** | One table entry per constructor, all distinct. Fewer means an unreachable route; duplicates mean an entry that can never be selected. |
| **DISPATCH-UNAMBIGUOUS** | No concrete target matches two entries — so installation ORDER cannot change any outcome. This is what makes generation safe, since a hand-written first-match router silently swallows a later pattern. |
| **DISPATCH-FAITHFUL** | The entry that matches a target belongs to the route `classify` returns for it. Complete and unambiguous is not enough: the table could still send a request to the wrong handler. |
| **CHAOS ORDER-INVARIANT** | 20 seeded scrambles of the install order route every witness and generated target identically. |
| **FUZZ DISPATCH** | 5000 raw byte targets: none raise, none are ambiguous. |
| **ROUTER-GENERATED** | The app installs no route by hand beside the table, with a non-vacuity guard that it installs the generated one. |
| **CLIENT-LINK-ZERO** | The Bonsai client contains NO hand-written API URL — all 20 are now derived from route values — with a non-vacuity guard requiring the client to actually call the route helpers. |

**COVERAGE is the law that keeps the rest honest.** Every other law is a
statement about the algebra in isolation, and an algebra that no longer
describes the running server is *worse* than no algebra, because it reads like
evidence.

---

## 7 · Mutants

| Mutant | Change | Verdict |
|---|---|---|
| **MUT-ROUTE-1** | `%` treated as unreserved, so it passes through unencoded | **SURVIVED, then killed** — see below |
| **MUT-ROUTE-2** | `to_path` drops the leading slash | Killed by CANONICITY |
| **MUT-ROUTE-3** | A route removed from the witness table | Killed by TOTALITY-OF-WITNESSES *and* COVERAGE-SERVED |
| **MUT-HTML-1** | `href` built from `pattern` instead of `to_path` | Killed by LINK-FROM-ROUTE |

**MUT-ROUTE-1 is the finding worth recording.** It survived the first run of
the ENCODING law, and the reason is instructive: the law's identifier list
contained `a%b`, which is a *malformed* escape. The decoder is deliberately
lenient about malformed escapes — it passes them through unchanged — so the
value round-trips whether or not `%` is encoded. A *well-formed* escape
discriminates immediately: `a%41b` comes back as `aAb`, and `%2F` comes back as
a segment separator. Adding `a%41b`, `%2F`, `100%25` and `%%` to the list
killed the mutant.

The general lesson, and the second time this session has produced it: **a
mutant that survives a law aimed at its behaviour means the law's INPUT was not
discriminating.** The law was right; the witness was weak.

---

## 8 · What is typed, and what is still not

Honest scope, because the point of the exercise is compile-time guarantees and
a partial one must not read as a complete one.

| Property | Status |
|---|---|
| A URL can only be produced from a route | **Compile-time** — no string-taking constructor exists |
| A route's parameters carry their real types | **Compile-time** — `Id.t` is abstract, `Job` carries `int` |
| A query value outside its variant | **Compile-time** for construction, rejected at runtime for parsing |
| The router serves exactly the declared routes | **Gate-time** — COVERAGE reads the router's source |
| The Bonsai client builds links from routes | **Done** — 0 literals; `LAW CLIENT-LINK-ZERO` keeps it there |
| The Dream router is generated from `Route.all` | **Done** — the table IS the router; a new route without a handler is a compile error |

The last two are the remaining work, and they are sequenced that way
deliberately: the algebra and its laws come first, so that converting the call
sites is a mechanical change verified by a law that already exists rather than
a rewrite verified by hope.
