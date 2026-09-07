import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import prng
import uos_swarm/acl.{Atom, Clause, VIdent, VNum}
import uos_swarm/board

const sutra_gita_sample = "@perf PROPOSE  ; test frame for sutra/gita headers
@from W03/L2 @to L0-fable
I(W03): integrate(x) ⇐ verdict(V1)=PASS
#aspects 3
#ca CA-integrate_slice
#onto Compositor
@sūtra S5.1,S1.2
@gītā 2.47"

const sample = "@perf PROPOSE  ; W03 proposes integration
@from W03/L2 @to L0-fable
@ooda decide
@conf 0.82
@cost 4014
K(W03): tests(palette)=14 ∧ warnings=0
B(W03): risk(diff)=low
I(W03): integrate(palette) ⇐ verdict(V1)=PASS
G: minimize(tokens) ∧ maximize(first_pass_yield)
∴ propose(integrate, slice=W03, epoch=7)
#aspects 3,13
#ca CA-integrate_slice
#onto Compositor|Worker
#muda Waiting"

pub fn parse_sample_test() {
  let u = case acl.parse(sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  u.perf |> should.equal(acl.Propose)
  u.from |> should.equal("W03")
  u.from_layer |> should.equal("L2")
  u.to |> should.equal("L0-fable")
  u.conf |> should.equal(Some(0.82))
  u.cost |> should.equal(Some(4014))
  list.length(u.clauses) |> should.equal(5)
  u.aspects |> should.equal([3, 13])
  u.concepts |> should.equal(["Compositor", "Worker"])
  case u.clauses {
    [
      Clause(
        acl.Knows("W03"),
        [
          Atom("tests", [VIdent("palette")], Some(VNum(14.0))),
          Atom("warnings", [], Some(VNum(0.0))),
        ],
        [],
      ),
      ..
    ] -> True
    _ -> False
  }
  |> should.be_true
  case list.drop(u.clauses, 2) {
    [
      Clause(
        acl.Intends("W03"),
        [Atom("integrate", [VIdent("palette")], None)],
        [Atom("verdict", [VIdent("V1")], Some(VIdent("PASS")))],
      ),
      ..
    ] -> True
    _ -> False
  }
  |> should.be_true
}

pub fn print_parse_roundtrip_test() {
  let u = case acl.parse(sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  acl.parse(acl.to_text(u)) |> should.equal(Ok(u))
}

pub fn validate_binds_vocabulary_and_modal_discipline_test() {
  let u = case acl.parse(sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  acl.validate(u) |> should.equal(Ok(Nil))
  acl.validate(acl.Utterance(..u, concepts: ["Nope"]))
  |> should.equal(Error("unknown ontology concept: Nope"))
  acl.validate(acl.Utterance(..u, control_actions: ["CA-x"]))
  |> should.equal(Error("unknown control action: CA-x"))
  // INFORM without K clause is rejected
  acl.validate(
    acl.Utterance(..u, perf: acl.Inform, clauses: [
      Clause(acl.Goal, [Atom("x", [], None)], []),
    ]),
  )
  |> should.equal(Error("INFORM needs a K(...) clause"))
  acl.validate(acl.Utterance(..u, perf: acl.Andon, control_actions: []))
  |> should.equal(Error("ANDON must name a control action (#ca)"))
  acl.validate(acl.Utterance(..u, perf: acl.Hypothesize, conf: Some(1.5)))
  |> should.equal(Error("HYPOTHESIZE needs a B(...) clause and @conf in (0,1)"))
}

pub fn parse_errors_are_specific_test() {
  acl.parse("@from a/L2 @to b\nK(a): x") |> should.equal(Error("missing @perf"))
  acl.parse("@perf INFORM\nK(a): x") |> should.equal(Error("missing @from"))
  acl.parse("@perf BOGUS\n@from a/L2 @to b")
  |> should.equal(Error("unknown performative BOGUS"))
  acl.parse("@perf INFORM\n@from a/L2 @to b\nhello world")
  |> fn(r) {
    case r {
      Error(e) -> string.contains(e, "clause must start")
      Ok(_) -> False
    }
  }
  |> should.be_true
  acl.parse("@perf INFORM\n@from a/L2 @to b\n@zzz 1")
  |> should.equal(Error("unknown directive @zzz"))
}

pub fn protocol_machine_test() {
  acl.protocol_step(acl.Open, acl.Request)
  |> should.equal(Ok(acl.AwaitingReply))
  acl.protocol_step(acl.AwaitingReply, acl.Accept)
  |> should.equal(Ok(acl.Committed))
  acl.protocol_step(acl.Committed, acl.Inform) |> should.equal(Ok(acl.Closed))
  acl.protocol_step(acl.Closed, acl.Inform)
  |> should.equal(Error("conversation closed"))
  acl.protocol_step(acl.Open, acl.Accept)
  |> fn(r) {
    case r {
      Error(_) -> True
      Ok(_) -> False
    }
  }
  |> should.be_true
}

pub fn semantics_defined_for_every_performative_test() {
  list.each(acl.performatives, fn(p) {
    let #(pre, post) = acl.semantics_of(p)
    { pre != "" && post != "" } |> should.be_true
    acl.performative_from(acl.performative_label(p)) |> should.equal(Ok(p))
  })
}

pub fn density_and_entropy_positive_test() {
  let u = case acl.parse(sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  { acl.density(u) >=. 0.3 } |> should.be_true
  { acl.entropy_bits(u) >. 3.0 } |> should.be_true
  { list.length(acl.introspect(u)) >= 8 } |> should.be_true
}

pub fn to_draft_is_a_valid_tracked_message_test() {
  let u = case acl.parse(sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  let d = acl.to_draft(u, "sonnet")
  d.kind |> should.equal(board.Plan)
  d.from.id |> should.equal("W03")
  board.validate_semantics(d.semantics) |> should.equal(Ok(Nil))
  list.any(d.payload, fn(p) {
    p.0 == "acl"
    && string.contains(p.1, "tasmāt propose(integrate")
    && string.contains(p.1, "; en: therefore propose(integrate")
  })
  |> should.be_true
}

// Property: printing any parsed utterance and parsing again is identity (over generated utterances).
pub fn property_roundtrip_generated_test() {
  list.each(prng.seeds(60), fn(seed) {
    let #(k, seed) = prng.int_between(seed, 0, 11)
    let perf =
      acl.performatives
      |> list.drop(k)
      |> list.first
      |> fn(r) {
        case r {
          Ok(p) -> p
          Error(_) -> acl.Inform
        }
      }
    let #(n, seed) = prng.int_between(seed, 1, 4)
    let #(vals, _) = prng.ints(seed, n, 0, 99)
    let clauses =
      list.index_map(vals, fn(v, i) {
        Clause(
          acl.Knows("A" <> string.inspect(i)),
          [
            Atom(
              "m" <> string.inspect(i),
              [VIdent("x")],
              Some(VNum(int_to_float(v))),
            ),
          ],
          [],
        )
      })
    let u =
      acl.Utterance(
        ..acl.empty(perf, "W01", "L2", "L0-fable"),
        clauses: clauses,
        aspects: [1, 17],
        control_actions: ["CA-emit_intent"],
        concepts: ["App"],
      )
    acl.parse(acl.to_text(u)) |> should.equal(Ok(u))
  })
}

fn int_to_float(i: Int) -> Float {
  case i {
    0 -> 0.0
    _ -> {
      let f = prng_float(i)
      f
    }
  }
}

@external(erlang, "erlang", "float")
fn prng_float(i: Int) -> Float

// Fuzz: parse never crashes.
pub fn fuzz_parse_test() {
  list.each(prng.seeds(300), fn(seed) {
    let #(t, _) = prng.text(seed, 60)
    let _ = acl.parse("@perf INFORM\n@from a/L2 @to b\n" <> t)
    let _ = acl.parse(t)
    Nil
  })
}

pub fn sanskrit_surface_forms_parse_to_same_utterance_test() {
  let english =
    "@perf REQUEST\n@from W01/L2 @to L0-fable\n@ooda decide\nI(W01): integrate(x) ⇐ verdict(V1)=PASS\n#aspects 3\n#ca CA-integrate_slice\n#onto Worker"
  let iast =
    "@kārya prārthanā\n@preṣaka W01/L2 @prāpaka L0-fable\n@cakra nirṇaya\niṣ(W01): integrate(x) cet verdict(V1)=PASS\n#pakṣa 3\n#niyantraṇa CA-integrate_slice\n#sattā Worker"
  let devanagari =
    "@कार्य प्रार्थना\n@प्रेषक W01/L2 @प्रापक L0-fable\n@चक्र निर्णय\nइष्(W01): integrate(x) चेत् verdict(V1)=PASS\n#पक्ष 3\n#नियन्त्रण CA-integrate_slice\n#सत्ता Worker"
  let a = acl.parse(english)
  acl.parse(iast) |> should.equal(a)
  acl.parse(devanagari) |> should.equal(a)
  case a {
    Ok(u) -> {
      u.perf |> should.equal(acl.Request)
      u.ooda |> should.equal(Some("decide"))
      // canonical print is Sanskrit-first with English beside every line, and round-trips
      let txt = acl.to_text(u)
      string.contains(txt, "@kārya prārthanā  ; en: @perf REQUEST")
      |> should.be_true
      string.contains(txt, "iṣ(W01):") |> should.be_true
      string.contains(txt, "; en: W01 intends") |> should.be_true
      acl.parse(txt) |> should.equal(Ok(u))
    }
    Error(_) -> should.fail()
  }
}

pub fn lexicon_is_complete_and_bijective_test() {
  list.each(acl.performatives, fn(p) {
    let sa = acl.to_iast("perf", acl.performative_label(p))
    { sa != acl.performative_label(p) } |> should.be_true
    acl.to_english("perf", sa) |> should.equal(acl.performative_label(p))
  })
  list.each(["perf", "from", "to", "re", "ooda", "conf", "cost", "by"], fn(d) {
    { acl.to_iast("dir", d) != d } |> should.be_true
  })
  list.each(["aspects", "ca", "onto", "muda"], fn(t) {
    { acl.to_iast("tag", t) != t } |> should.be_true
  })
  list.each(acl.lexicon, fn(l) {
    { l.devanagari != "" && l.gloss != "" } |> should.be_true
  })
  string.contains(acl.lexicon_markdown(), "| perf | INFORM | sūcanā | सूचना |")
  |> should.be_true
}

pub fn sutra_and_gita_headers_parse_test() {
  let u = case acl.parse(sutra_gita_sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  u.sutras |> should.equal(["S5.1", "S1.2"])
  u.gita |> should.equal(["2.47"])
}

pub fn sutra_and_gita_rendering_carries_gloss_test() {
  let u = case acl.parse(sutra_gita_sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  let txt = acl.to_text(u)
  string.contains(txt, "@sūtra S5.1  ; en: sutra S5.1") |> should.be_true
  string.contains(txt, "@sūtra S1.2  ; en: sutra S1.2") |> should.be_true
  string.contains(txt, "@gītā 2.47  ; en: BG 2.47") |> should.be_true
}

pub fn sutra_and_gita_headers_roundtrip_preserves_ids_test() {
  let u = case acl.parse(sutra_gita_sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  let u2 = case acl.parse(acl.to_text(u)) {
    Ok(x) -> x
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  u2.sutras |> should.equal(u.sutras)
  u2.gita |> should.equal(u.gita)
  acl.parse(acl.to_text(u)) |> should.equal(Ok(u))
}

pub fn sutra_and_gita_validation_test() {
  let u = case acl.parse(sample) {
    Ok(u) -> u
    Error(_) -> acl.empty(acl.Andon, "x", "L3", "y")
  }
  // unknown sutra id
  acl.validate(acl.Utterance(..u, sutras: ["S99.99"]))
  |> should.equal(Error("unknown sutra: S99.99"))
  // a sutra that exists but does not govern this utterance's kind (Plan)
  acl.validate(acl.Utterance(..u, sutras: ["S5.4"]))
  |> should.equal(Error("sutra S5.4 does not govern kind Plan"))
  // a sutra that does govern this kind is accepted
  acl.validate(acl.Utterance(..u, sutras: ["S2.1"]))
  |> should.equal(Ok(Nil))
  // unknown gita citation
  acl.validate(acl.Utterance(..u, gita: ["99.99"]))
  |> should.equal(Error("unknown gita citation: 99.99"))
  // a real gita citation is accepted
  acl.validate(acl.Utterance(..u, gita: ["2.47"]))
  |> should.equal(Ok(Nil))
}
