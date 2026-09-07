//// UOS Agent Communication Language (ACL): a formal, typed, human-readable language for
//// agent-to-agent and agent-to-system communication, optimised for sharing thinking at high
//// information density and for interpretability/introspection.
////
//// Syntax (line-oriented; `;` starts a comment):
////   @perf REQUEST                 performative (FIPA-style, closed set)
////   @from W03/L2  @to L0-fable    addressing (agent/layer)
////   @re <id>  @ooda decide  @conf 0.82  @cost 1200  @by 2026-09-07T05:10:00Z
////   K(W03): tests(palette)=14 ∧ warnings=0        epistemic: the speaker KNOWS
////   B(W03): risk(diff)=low                          doxastic: BELIEVES
////   I(W03): integrate(palette) ⇐ verdict(V1)=PASS  intention with precondition (⇐ requires)
////   O(W03): reply(L0-fable) ⇐ deadline=300s        obligation (deontic)
////   G: minimize(tokens) ∧ maximize(first_pass_yield)   goals
////   ∴ propose(integrate, slice=W03, epoch=7)      conclusion / proposed action
////   #aspects 3,13  #ca CA-integrate_slice  #onto Compositor|Worker  #muda Waiting
//// Semantics: performatives carry pre/post conditions on shared state (K/B/I/O sets) and a
//// conversation protocol (bounded finite state machine). Every reference is bound to the
//// ontology, aspects, STPA control actions and muda vocabulary; unbound symbols fail closed.
//// Density: bits/token (Shannon) and semantic references per token.
//// STAMP: SC-TUI-ACL-001, #rocha-semiotics (symbol layer decoupled from execution).

import gleam/dict
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import uos_tui/board.{type Draft, Agent, Causality, Draft, Semantics}

// ---------------------------------------------------------------------------
// Performatives with formal semantics
// ---------------------------------------------------------------------------

pub type Performative {
  Inform
  Request
  Propose
  Accept
  Reject
  Query
  Confirm
  Commit
  Assert
  Retract
  Hypothesize
  Andon
}

pub const performatives = [
  Inform,
  Request,
  Propose,
  Accept,
  Reject,
  Query,
  Confirm,
  Commit,
  Assert,
  Retract,
  Hypothesize,
  Andon,
]

pub fn performative_label(p: Performative) -> String {
  case p {
    Inform -> "INFORM"
    Request -> "REQUEST"
    Propose -> "PROPOSE"
    Accept -> "ACCEPT"
    Reject -> "REJECT"
    Query -> "QUERY"
    Confirm -> "CONFIRM"
    Commit -> "COMMIT"
    Assert -> "ASSERT"
    Retract -> "RETRACT"
    Hypothesize -> "HYPOTHESIZE"
    Andon -> "ANDON"
  }
}

pub fn performative_from(s: String) -> Result(Performative, String) {
  let key = to_english("perf", string.trim(s))
  performatives
  |> list.find(fn(p) { performative_label(p) == key })
  |> result.replace_error("unknown performative " <> s)
}

/// Formal effect of a performative on the shared modal state: (precondition, postcondition).
pub fn semantics_of(p: Performative) -> #(String, String) {
  case p {
    Inform -> #("B(s, φ) ∧ ¬B(s, K(r, φ))", "K(r, φ)")
    Request -> #(
      "I(s, done(a)) ∧ ¬B(s, I(r, done(a)))",
      "O(r, reply ∈ {ACCEPT, REJECT})",
    )
    Propose -> #(
      "B(s, feasible(a))",
      "O(r, reply ∈ {ACCEPT, REJECT}) ∧ B(r, I(s, a))",
    )
    Accept -> #(
      "O(s, reply) ∧ B(s, feasible(a))",
      "I(s, done(a)) ∧ ¬O(s, reply)",
    )
    Reject -> #("O(s, reply)", "¬I(s, done(a)) ∧ ¬O(s, reply) ∧ K(r, reason)")
    Query -> #("¬K(s, φ) ∧ B(s, K(r, φ))", "O(r, INFORM(φ))")
    Confirm -> #("B(s, φ) ∧ B(s, U(r, φ))", "K(r, φ)")
    Commit -> #("I(s, done(a))", "O(s, done(a) before deadline)")
    Assert -> #("K(s, φ)", "K(r, φ) ∧ φ ∈ ledger")
    Retract -> #("K(r, φ) via s", "¬K(r, φ) ∧ retracted(φ) ∈ ledger")
    Hypothesize -> #("¬K(s, φ) ∧ p(φ) ∈ (0,1)", "B(r, p(φ)) ∧ O(any, test(φ))")
    Andon -> #("B(s, hazard)", "O(L0∪L1, decide) ∧ line_state ∈ {yellow, red}")
  }
}

/// Bounded conversation protocol: which performative may follow which (FIPA request/propose protocols).
pub type Conv {
  Open
  AwaitingReply
  Committed
  Closed
}

pub fn protocol_step(state: Conv, p: Performative) -> Result(Conv, String) {
  case state, p {
    Open, Request | Open, Propose | Open, Query -> Ok(AwaitingReply)
    Open, Inform
    | Open, Assert
    | Open, Confirm
    | Open, Hypothesize
    | Open, Andon
    | Open, Retract
    -> Ok(Open)
    Open, Commit -> Ok(Committed)
    AwaitingReply, Accept -> Ok(Committed)
    AwaitingReply, Reject -> Ok(Closed)
    AwaitingReply, Inform -> Ok(Closed)
    AwaitingReply, Andon -> Ok(AwaitingReply)
    Committed, Inform | Committed, Confirm -> Ok(Closed)
    Committed, Retract -> Ok(Closed)
    Committed, Andon -> Ok(Committed)
    Closed, _ -> Error("conversation closed")
    s, p ->
      Error(performative_label(p) <> " not allowed in state " <> conv_label(s))
  }
}

pub fn conv_label(c: Conv) -> String {
  case c {
    Open -> "open"
    AwaitingReply -> "awaiting-reply"
    Committed -> "committed"
    Closed -> "closed"
  }
}

// ---------------------------------------------------------------------------
// Lexicon: Sanskrit (IAST + Devanagari) mirrors for every keyword, with English gloss.
// The parser accepts English, IAST or Devanagari; the canonical printer emits IAST with
// the English form beside it, so every utterance reads for Sanskrit and English readers.
// ---------------------------------------------------------------------------

pub type Lexeme {
  Lexeme(
    role: String,
    english: String,
    iast: String,
    devanagari: String,
    gloss: String,
  )
}

pub const lexicon = [
  // performatives (kārya)
  Lexeme("perf", "INFORM", "sūcanā", "सूचना", "notice, information"),
  Lexeme("perf", "REQUEST", "prārthanā", "प्रार्थना", "request, petition"),
  Lexeme("perf", "PROPOSE", "prastāva", "प्रस्ताव", "proposal"),
  Lexeme("perf", "ACCEPT", "svīkāra", "स्वीकार", "acceptance"),
  Lexeme("perf", "REJECT", "nirākaraṇa", "निराकरण", "rejection"),
  Lexeme("perf", "QUERY", "praśna", "प्रश्न", "question"),
  Lexeme("perf", "CONFIRM", "puṣṭi", "पुष्टि", "confirmation"),
  Lexeme("perf", "COMMIT", "saṅkalpa", "सङ्कल्प", "resolve, vow"),
  Lexeme("perf", "ASSERT", "pratijñā", "प्रतिज्ञा", "assertion"),
  Lexeme("perf", "RETRACT", "pratyāhāra", "प्रत्याहार", "withdrawal"),
  Lexeme("perf", "HYPOTHESIZE", "kalpanā", "कल्पना", "hypothesis"),
  Lexeme("perf", "ANDON", "sāvadhāna", "सावधान", "alert, attention"),
  // modals
  Lexeme("modal", "K", "jñā", "ज्ञा", "knows"),
  Lexeme("modal", "B", "man", "मन्", "believes, thinks"),
  Lexeme("modal", "I", "iṣ", "इष्", "intends, wills"),
  Lexeme("modal", "O", "kṛtya", "कृत्य", "is obliged, duty"),
  Lexeme("modal", "G", "lakṣya", "लक्ष्य", "goal"),
  Lexeme("modal", "∴", "tasmāt", "तस्मात्", "therefore"),
  // header directives
  Lexeme("dir", "perf", "kārya", "कार्य", "act, performative"),
  Lexeme("dir", "from", "preṣaka", "प्रेषक", "sender"),
  Lexeme("dir", "to", "prāpaka", "प्रापक", "receiver"),
  Lexeme("dir", "re", "uttara", "उत्तर", "reply to"),
  Lexeme("dir", "ooda", "cakra", "चक्र", "cycle phase"),
  Lexeme("dir", "conf", "niścaya", "निश्चय", "certainty"),
  Lexeme("dir", "cost", "mūlya", "मूल्य", "cost"),
  Lexeme("dir", "by", "samaya", "समय", "deadline"),
  // tags
  Lexeme("tag", "aspects", "pakṣa", "पक्ष", "aspects"),
  Lexeme("tag", "ca", "niyantraṇa", "नियन्त्रण", "control actions"),
  Lexeme("tag", "onto", "sattā", "सत्ता", "ontology concepts"),
  Lexeme("tag", "muda", "vyartha", "व्यर्थ", "waste"),
  // connectives and OODA phases
  Lexeme("conn", "∧", "ca", "च", "and"),
  Lexeme("conn", "⇐", "cet", "चेत्", "provided that"),
  Lexeme("ooda", "observe", "avalokana", "अवलोकन", "observe"),
  Lexeme("ooda", "orient", "vicāra", "विचार", "consider, orient"),
  Lexeme("ooda", "decide", "nirṇaya", "निर्णय", "decide"),
  Lexeme("ooda", "act", "kriyā", "क्रिया", "act"),
]

/// Resolve any surface form (English, IAST, Devanagari) of a role to its English key.
pub fn to_english(role: String, word: String) -> String {
  let w = string.trim(word)
  lexicon
  |> list.find(fn(l) {
    l.role == role && { l.english == w || l.iast == w || l.devanagari == w }
  })
  |> result.map(fn(l) { l.english })
  |> result.unwrap(w)
}

/// IAST form of an English key (identity when unknown).
pub fn to_iast(role: String, english: String) -> String {
  lexicon
  |> list.find(fn(l) { l.role == role && l.english == english })
  |> result.map(fn(l) { l.iast })
  |> result.unwrap(english)
}

pub fn lexicon_markdown() -> String {
  let header =
    "| role | English | IAST | Devanagari | gloss |\n|---|---|---|---|---|"
  let rows =
    list.map(lexicon, fn(l) {
      "| "
      <> l.role
      <> " | "
      <> l.english
      <> " | "
      <> l.iast
      <> " | "
      <> l.devanagari
      <> " | "
      <> l.gloss
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

pub type Value {
  VIdent(String)
  VNum(Float)
  VStr(String)
  VPair(key: String, value: Value)
}

/// `pred(args)`, `key=value`, or `pred(args)=value`.
pub type Atom {
  Atom(pred: String, args: List(Value), value: Option(Value))
}

pub type Modal {
  Knows(agent: String)
  Believes(agent: String)
  Intends(agent: String)
  Obliged(agent: String)
  Goal
  Therefore
}

/// A clause: modal prefix, conjunction of atoms, optional precondition (⇐) conjunction.
pub type Clause {
  Clause(modal: Modal, atoms: List(Atom), requires: List(Atom))
}

pub type Utterance {
  Utterance(
    perf: Performative,
    from: String,
    from_layer: String,
    to: String,
    re: Option(String),
    ooda: Option(String),
    conf: Option(Float),
    cost: Option(Int),
    by: Option(String),
    clauses: List(Clause),
    aspects: List(Int),
    control_actions: List(String),
    concepts: List(String),
    muda: List(String),
  )
}

pub fn empty(
  perf: Performative,
  from: String,
  from_layer: String,
  to: String,
) -> Utterance {
  Utterance(
    perf,
    from,
    from_layer,
    to,
    None,
    None,
    None,
    None,
    None,
    [],
    [],
    [],
    [],
    [],
  )
}

// ---------------------------------------------------------------------------
// Printer (canonical) and parser
// ---------------------------------------------------------------------------

fn value_text(v: Value) -> String {
  case v {
    VIdent(s) -> s
    VNum(f) -> num_text(f)
    VStr(s) -> "\"" <> string.replace(s, "\"", "\\\"") <> "\""
    VPair(k, inner) -> k <> "=" <> value_text(inner)
  }
}

fn num_text(f: Float) -> String {
  let i = float.truncate(f)
  case int.to_float(i) == f {
    True -> int.to_string(i)
    False -> float.to_string(f)
  }
}

pub fn atom_text(a: Atom) -> String {
  let head = case a.args {
    [] -> a.pred
    args ->
      a.pred <> "(" <> string.join(list.map(args, value_text), ", ") <> ")"
  }
  case a.value {
    Some(v) -> head <> "=" <> value_text(v)
    None -> head
  }
}

fn modal_text(m: Modal) -> String {
  case m {
    Knows(a) -> "jñā(" <> a <> "):"
    Believes(a) -> "man(" <> a <> "):"
    Intends(a) -> "iṣ(" <> a <> "):"
    Obliged(a) -> "kṛtya(" <> a <> "):"
    Goal -> "lakṣya:"
    Therefore -> "tasmāt"
  }
}

fn modal_english(m: Modal) -> String {
  case m {
    Knows(a) -> a <> " knows"
    Believes(a) -> a <> " believes"
    Intends(a) -> a <> " intends"
    Obliged(a) -> a <> " is obliged"
    Goal -> "goal"
    Therefore -> "therefore"
  }
}

pub fn clause_text(c: Clause) -> String {
  let body = string.join(list.map(c.atoms, atom_text), " ∧ ")
  let core = case c.requires {
    [] -> modal_text(c.modal) <> " " <> body
    r ->
      modal_text(c.modal)
      <> " "
      <> body
      <> " ⇐ "
      <> string.join(list.map(r, atom_text), " ∧ ")
  }
  core
  <> "  ; en: "
  <> modal_english(c.modal)
  <> " "
  <> string.join(list.map(c.atoms, atom_text), " and ")
  <> case c.requires {
    [] -> ""
    r -> ", provided " <> string.join(list.map(r, atom_text), " and ")
  }
}

/// Canonical text form: header directives, clauses, then reference tags.
pub fn to_text(u: Utterance) -> String {
  let opt = fn(key, v: Option(String)) {
    case v {
      Some(x) -> [key <> " " <> x]
      None -> []
    }
  }
  let header =
    list.flatten([
      [
        "@kārya "
        <> to_iast("perf", performative_label(u.perf))
        <> "  ; en: @perf "
        <> performative_label(u.perf),
      ],
      [
        "@preṣaka "
        <> u.from
        <> "/"
        <> u.from_layer
        <> " @prāpaka "
        <> u.to
        <> "  ; en: @from "
        <> u.from
        <> "/"
        <> u.from_layer
        <> " @to "
        <> u.to,
      ],
      opt("@uttara", u.re),
      opt(
        "@cakra",
        option.map(u.ooda, fn(o) { to_iast("ooda", o) <> "  ; en: @ooda " <> o }),
      ),
      opt("@niścaya", option.map(u.conf, float.to_string)),
      opt("@mūlya", option.map(u.cost, int.to_string)),
      opt("@samaya", u.by),
    ])
  let tags =
    list.flatten([
      case u.aspects {
        [] -> []
        a -> [
          "#pakṣa "
          <> string.join(list.map(a, int.to_string), ",")
          <> "  ; en: #aspects",
        ]
      },
      case u.control_actions {
        [] -> []
        c -> [
          "#niyantraṇa " <> string.join(c, ",") <> "  ; en: #ca control actions",
        ]
      },
      case u.concepts {
        [] -> []
        c -> ["#sattā " <> string.join(c, "|") <> "  ; en: #onto concepts"]
      },
      case u.muda {
        [] -> []
        m -> ["#vyartha " <> string.join(m, ",") <> "  ; en: #muda waste"]
      },
    ])
  string.join(
    list.flatten([header, list.map(u.clauses, clause_text), tags]),
    "\n",
  )
}

fn strip_comment(line: String) -> String {
  case string.split_once(line, ";") {
    Ok(#(code, _)) -> string.trim(code)
    Error(_) -> string.trim(line)
  }
}

/// Normalise a line: Sanskrit (IAST/Devanagari) directives, tags, modals and connectives to
/// their English/symbolic forms so one parser serves every surface form.
pub fn normalise(line: String) -> String {
  let line =
    line
    |> string.replace(" ca ", " ∧ ")
    |> string.replace(" च ", " ∧ ")
    |> string.replace(" cet ", " ⇐ ")
    |> string.replace(" चेत् ", " ⇐ ")
  let line = case line {
    "@" <> rest ->
      case string.split_once(rest, " ") {
        Ok(#(key, v)) -> "@" <> to_english("dir", key) <> " " <> v
        Error(_) -> line
      }
    "#" <> rest ->
      case string.split_once(rest, " ") {
        Ok(#(key, v)) -> "#" <> to_english("tag", key) <> " " <> v
        Error(_) -> line
      }
    _ -> line
  }
  let line = case line {
    "@from " <> rest ->
      "@from "
      <> {
        rest
        |> string.replace(" @prāpaka ", " @to ")
        |> string.replace(" @प्रापक ", " @to ")
      }
    "@ooda " <> rest -> "@ooda " <> to_english("ooda", rest)
    _ -> line
  }
  list.fold(
    [
      #("jñā(", "K("),
      #("ज्ञा(", "K("),
      #("man(", "B("),
      #("मन्(", "B("),
      #("iṣ(", "I("),
      #("इष्(", "I("),
      #("kṛtya(", "O("),
      #("कृत्य(", "O("),
      #("lakṣya:", "G:"),
      #("लक्ष्य:", "G:"),
      #("tasmāt", "∴"),
      #("तस्मात्", "∴"),
    ],
    line,
    fn(l, pair) {
      case string.starts_with(l, pair.0) {
        True -> pair.1 <> string.drop_start(l, string.length(pair.0))
        False -> l
      }
    },
  )
}

pub fn parse(text: String) -> Result(Utterance, String) {
  let lines =
    text
    |> string.split("\n")
    |> list.map(strip_comment)
    |> list.filter(fn(l) { l != "" })
    |> list.map(normalise)
  use perf_line <- result.try(
    lines
    |> list.find(fn(l) { string.starts_with(l, "@perf ") })
    |> result.replace_error("missing @perf"),
  )
  use perf <- result.try(
    performative_from(string.trim(string.drop_start(perf_line, 6))),
  )
  use from_line <- result.try(
    lines
    |> list.find(fn(l) { string.starts_with(l, "@from ") })
    |> result.replace_error("missing @from"),
  )
  use #(from, layer, to) <- result.try(parse_from(from_line))
  let u = empty(perf, from, layer, to)
  list.try_fold(lines, u, fn(u, line) {
    case line {
      "@perf " <> _ | "@from " <> _ -> Ok(u)
      "@re " <> v -> Ok(Utterance(..u, re: Some(string.trim(v))))
      "@ooda " <> v -> Ok(Utterance(..u, ooda: Some(string.trim(v))))
      "@conf " <> v ->
        float.parse(string.trim(v))
        |> result.map(fn(f) { Utterance(..u, conf: Some(f)) })
        |> result.replace_error("bad @conf " <> v)
      "@cost " <> v ->
        int.parse(string.trim(v))
        |> result.map(fn(i) { Utterance(..u, cost: Some(i)) })
        |> result.replace_error("bad @cost " <> v)
      "@by " <> v -> Ok(Utterance(..u, by: Some(string.trim(v))))
      "#aspects " <> v ->
        Ok(
          Utterance(
            ..u,
            aspects: v
              |> string.split(",")
              |> list.filter_map(fn(x) { int.parse(string.trim(x)) }),
          ),
        )
      "#ca " <> v -> Ok(Utterance(..u, control_actions: split_list(v, ",")))
      "#onto " <> v -> Ok(Utterance(..u, concepts: split_list(v, "|")))
      "#muda " <> v -> Ok(Utterance(..u, muda: split_list(v, ",")))
      "@" <> other ->
        Error(
          "unknown directive @"
          <> {
            other |> string.split(" ") |> list.first |> result.unwrap(other)
          },
        )
      "#" <> other ->
        Error(
          "unknown tag #"
          <> {
            other |> string.split(" ") |> list.first |> result.unwrap(other)
          },
        )
      clause_line ->
        parse_clause(clause_line)
        |> result.map(fn(c) {
          Utterance(..u, clauses: list.append(u.clauses, [c]))
        })
    }
  })
}

fn split_list(v: String, sep: String) -> List(String) {
  v
  |> string.split(sep)
  |> list.map(string.trim)
  |> list.filter(fn(x) { x != "" })
}

fn parse_from(line: String) -> Result(#(String, String, String), String) {
  // "@from W03/L2 @to L0-fable"
  let rest = string.trim(string.drop_start(line, 6))
  case string.split_once(rest, " @to ") {
    Ok(#(f, t)) ->
      case string.split_once(string.trim(f), "/") {
        Ok(#(id, layer)) -> Ok(#(id, layer, string.trim(t)))
        Error(_) -> Ok(#(string.trim(f), "L3", string.trim(t)))
      }
    Error(_) -> Error("@from needs '@to': " <> line)
  }
}

fn parse_clause(line: String) -> Result(Clause, String) {
  use #(modal, rest) <- result.try(parse_modal(line))
  let #(body, req) = case string.split_once(rest, "⇐") {
    Ok(#(b, r)) -> #(b, r)
    Error(_) -> #(rest, "")
  }
  use atoms <- result.try(parse_conj(body))
  use requires <- result.try(case string.trim(req) {
    "" -> Ok([])
    r -> parse_conj(r)
  })
  case atoms {
    [] -> Error("empty clause: " <> line)
    _ -> Ok(Clause(modal, atoms, requires))
  }
}

fn parse_modal(line: String) -> Result(#(Modal, String), String) {
  case line {
    "∴" <> rest -> Ok(#(Therefore, rest))
    "G:" <> rest -> Ok(#(Goal, rest))
    "K(" <> rest -> modal_agent(rest, Knows)
    "B(" <> rest -> modal_agent(rest, Believes)
    "I(" <> rest -> modal_agent(rest, Intends)
    "O(" <> rest -> modal_agent(rest, Obliged)
    _ -> Error("clause must start with K( B( I( O( G: or ∴: " <> line)
  }
}

fn modal_agent(
  rest: String,
  mk: fn(String) -> Modal,
) -> Result(#(Modal, String), String) {
  case string.split_once(rest, "):") {
    Ok(#(agent, body)) -> Ok(#(mk(string.trim(agent)), body))
    Error(_) -> Error("modal needs 'agent):' " <> rest)
  }
}

fn parse_conj(text: String) -> Result(List(Atom), String) {
  text
  |> string.split("∧")
  |> list.map(string.trim)
  |> list.filter(fn(t) { t != "" })
  |> list.try_map(parse_atom)
}

fn parse_atom(text: String) -> Result(Atom, String) {
  // split trailing "=value" that is outside parentheses
  let #(head, value) = case split_value(text) {
    Some(#(h, v)) -> #(h, Some(v))
    None -> #(text, None)
  }
  use value <- result.try(case value {
    Some(v) -> parse_value(v) |> result.map(Some)
    None -> Ok(None)
  })
  case string.split_once(head, "(") {
    Ok(#(pred, args_close)) ->
      case string.ends_with(args_close, ")") {
        True -> {
          let args =
            args_close
            |> string.drop_end(1)
            |> string.split(",")
            |> list.map(string.trim)
            |> list.filter(fn(a) { a != "" })
          use args <- result.try(list.try_map(args, parse_value))
          ident_ok(string.trim(pred))
          |> result.map(fn(p) { Atom(p, args, value) })
        }
        False -> Error("unclosed '(' in " <> text)
      }
    Error(_) ->
      ident_ok(string.trim(head)) |> result.map(fn(p) { Atom(p, [], value) })
  }
}

fn split_value(text: String) -> Option(#(String, String)) {
  // find last '=' at paren depth 0
  let chars = string.to_graphemes(text)
  let #(_, idx, _) =
    list.index_fold(chars, #(0, -1, 0), fn(acc, ch, i) {
      let #(depth, found, _) = acc
      case ch {
        "(" -> #(depth + 1, found, i)
        ")" -> #(depth - 1, found, i)
        "=" if depth == 0 -> #(depth, i, i)
        _ -> #(depth, found, i)
      }
    })
  case idx >= 0 {
    True ->
      Some(#(
        string.trim(string.slice(text, 0, idx)),
        string.trim(string.drop_start(text, idx + 1)),
      ))
    False -> None
  }
}

fn ident_ok(s: String) -> Result(String, String) {
  case s != "" && list.all(string.to_graphemes(s), is_ident_char) {
    True -> Ok(s)
    False -> Error("bad identifier '" <> s <> "'")
  }
}

fn is_ident_char(c: String) -> Bool {
  case c {
    "_" | "-" | "." | "/" | ":" -> True
    _ -> {
      let n =
        c
        |> string.to_utf_codepoints
        |> list.first
        |> result.map(string.utf_codepoint_to_int)
        |> result.unwrap(0)
      { n >= 48 && n <= 57 }
      || { n >= 65 && n <= 90 }
      || { n >= 97 && n <= 122 }
    }
  }
}

fn parse_value(v: String) -> Result(Value, String) {
  let v = string.trim(v)
  case string.split_once(v, "=") {
    Ok(#(k, rest)) if k != "" -> {
      use key <- result.try(ident_ok(string.trim(k)))
      use inner <- result.try(parse_value(rest))
      Ok(VPair(key, inner))
    }
    _ -> parse_scalar(v)
  }
}

fn parse_scalar(v: String) -> Result(Value, String) {
  let v = string.trim(v)
  case
    string.starts_with(v, "\"")
    && string.ends_with(v, "\"")
    && string.length(v) >= 2
  {
    True ->
      Ok(VStr(
        v
        |> string.drop_start(1)
        |> string.drop_end(1)
        |> string.replace("\\\"", "\""),
      ))
    False ->
      case float.parse(v) {
        Ok(f) -> Ok(VNum(f))
        Error(_) ->
          case int.parse(v) {
            Ok(i) -> Ok(VNum(int.to_float(i)))
            Error(_) -> ident_ok(v) |> result.map(VIdent)
          }
      }
  }
}

// ---------------------------------------------------------------------------
// Semantic validation (vocabulary binding) and information density
// ---------------------------------------------------------------------------

/// Bind references to the shared vocabulary (ontology, aspects, STPA, muda) and check the
/// modal discipline: a REQUEST/PROPOSE must carry an I or ∴ clause; an INFORM/ASSERT a K clause;
/// a HYPOTHESIZE a B clause with @conf in (0,1); an ANDON must name a control action.
pub fn validate(u: Utterance) -> Result(Nil, String) {
  use _ <- result.try(
    board.validate_semantics(Semantics(
      u.concepts,
      u.aspects,
      u.control_actions,
      u.muda,
      layer_int(u.from_layer),
    )),
  )
  let has = fn(pred: fn(Modal) -> Bool) {
    list.any(u.clauses, fn(c) { pred(c.modal) })
  }
  let is_k = fn(m) {
    case m {
      Knows(_) -> True
      _ -> False
    }
  }
  let is_i_or_t = fn(m) {
    case m {
      Intends(_) | Therefore -> True
      _ -> False
    }
  }
  let is_b = fn(m) {
    case m {
      Believes(_) -> True
      _ -> False
    }
  }
  case u.perf {
    Request | Propose | Commit ->
      case has(is_i_or_t) {
        True -> Ok(Nil)
        False ->
          Error(performative_label(u.perf) <> " needs an I(...) or ∴ clause")
      }
    Inform | Assert | Confirm ->
      case has(is_k) {
        True -> Ok(Nil)
        False -> Error(performative_label(u.perf) <> " needs a K(...) clause")
      }
    Hypothesize ->
      case has(is_b), u.conf {
        True, Some(c) if c >. 0.0 && c <. 1.0 -> Ok(Nil)
        _, _ -> Error("HYPOTHESIZE needs a B(...) clause and @conf in (0,1)")
      }
    Andon ->
      case u.control_actions {
        [] -> Error("ANDON must name a control action (#ca)")
        _ -> Ok(Nil)
      }
    _ -> Ok(Nil)
  }
}

fn layer_int(layer: String) -> Int {
  layer |> string.drop_start(1) |> int.parse |> result.unwrap(3)
}

/// Dense canonical form: the bilingual text with English glosses removed (what the metrics measure).
pub fn to_text_dense(u: Utterance) -> String {
  to_text(u)
  |> string.split("\n")
  |> list.map(fn(l) {
    case string.split_once(l, "  ; en:") {
      Ok(#(core, _)) -> core
      Error(_) -> l
    }
  })
  |> string.join("\n")
}

pub fn tokens(u: Utterance) -> List(String) {
  to_text_dense(u)
  |> string.replace("\n", " ")
  |> string.split(" ")
  |> list.map(fn(t) { string.trim(t) })
  |> list.filter(fn(t) { t != "" })
}

/// Shannon entropy of the token distribution, bits per token.
pub fn entropy_bits(u: Utterance) -> Float {
  let ts = tokens(u)
  let n = int.to_float(list.length(ts))
  case n {
    0.0 -> 0.0
    _ -> {
      let counts =
        list.fold(ts, dict.new(), fn(d, t) {
          dict.upsert(d, t, fn(x) { option.unwrap(x, 0) + 1 })
        })
      counts
      |> dict.values
      |> list.fold(0.0, fn(acc, c) {
        let p = int.to_float(c) /. n
        acc -. p *. log2(p)
      })
    }
  }
}

fn log2(x: Float) -> Float {
  case float.logarithm(x) {
    Ok(ln) -> ln /. 0.6931471805599453
    Error(_) -> 0.0
  }
}

/// Semantic references (aspects + control actions + concepts + muda + atoms) per token.
pub fn density(u: Utterance) -> Float {
  let refs =
    list.length(u.aspects)
    + list.length(u.control_actions)
    + list.length(u.concepts)
    + list.length(u.muda)
    + list.fold(u.clauses, 0, fn(acc, c) {
      acc + list.length(c.atoms) + list.length(c.requires)
    })
  case list.length(tokens(u)) {
    0 -> 0.0
    n -> int.to_float(refs) /. int.to_float(n)
  }
}

/// Plain-language introspection of an utterance: what it does to the shared state and why.
pub fn introspect(u: Utterance) -> List(String) {
  let #(pre, post) = semantics_of(u.perf)
  let head =
    u.from
    <> " ("
    <> u.from_layer
    <> ") "
    <> string.lowercase(performative_label(u.perf))
    <> "s "
    <> u.to
    <> case u.re {
      Some(r) -> " in reply to " <> r
      None -> ""
    }
  let modal_lines =
    list.map(u.clauses, fn(c) {
      let who = case c.modal {
        Knows(a) -> a <> " knows that "
        Believes(a) -> a <> " believes that "
        Intends(a) -> a <> " intends to "
        Obliged(a) -> a <> " is obliged to "
        Goal -> "goal: "
        Therefore -> "therefore: "
      }
      who
      <> string.join(list.map(c.atoms, atom_text), " and ")
      <> case c.requires {
        [] -> ""
        r -> ", provided " <> string.join(list.map(r, atom_text), " and ")
      }
    })
  list.flatten([
    [head, "precondition: " <> pre, "postcondition: " <> post],
    modal_lines,
    [
      "references: aspects "
        <> string.join(list.map(u.aspects, int.to_string), ",")
        <> "; control actions "
        <> string.join(u.control_actions, ",")
        <> "; concepts "
        <> string.join(u.concepts, "|"),
      "density "
        <> float.to_string(float_round2(density(u)))
        <> " refs/token; entropy "
        <> float.to_string(float_round2(entropy_bits(u)))
        <> " bits/token",
    ],
  ])
}

fn float_round2(f: Float) -> Float {
  int.to_float(float.round(f *. 100.0)) /. 100.0
}

// ---------------------------------------------------------------------------
// Bridge to the message board
// ---------------------------------------------------------------------------

pub fn kind_for(p: Performative) -> board.Kind {
  case p {
    Inform | Assert | Confirm -> board.Report
    Request | Query -> board.Question
    Propose | Hypothesize -> board.Plan
    Accept | Reject -> board.Answer
    Commit -> board.Claim
    Retract -> board.Progress
    Andon -> board.Andon
  }
}

/// A board draft whose payload carries the canonical ACL text plus indexed fields.
pub fn to_draft(u: Utterance, model: String) -> Draft {
  let payload =
    list.flatten([
      [#("acl", to_text(u)), #("perf", performative_label(u.perf))],
      case u.ooda {
        Some(o) -> [#("ooda", o)]
        None -> []
      },
      case u.conf {
        Some(c) -> [#("conf", float.to_string(c))]
        None -> []
      },
      case u.cost {
        Some(c) -> [#("cost", int.to_string(c))]
        None -> []
      },
      [
        #("density", float.to_string(float_round2(density(u)))),
        #("entropy_bits", float.to_string(float_round2(entropy_bits(u)))),
      ],
    ])
  Draft(
    Agent(u.from, u.from_layer, model),
    u.to,
    kind_for(u.perf),
    payload,
    Semantics(
      u.concepts,
      u.aspects,
      u.control_actions,
      u.muda,
      layer_int(u.from_layer),
    ),
    Causality(u.re, []),
    None,
    None,
  )
}

pub fn to_json(u: Utterance) -> Json {
  json.object([
    #("perf", json.string(performative_label(u.perf))),
    #("from", json.string(u.from)),
    #("from_layer", json.string(u.from_layer)),
    #("to", json.string(u.to)),
    #("re", case u.re {
      Some(r) -> json.string(r)
      None -> json.null()
    }),
    #("clauses", json.array(u.clauses, fn(c) { json.string(clause_text(c)) })),
    #("aspects", json.array(u.aspects, json.int)),
    #("control_actions", json.array(u.control_actions, json.string)),
    #("concepts", json.array(u.concepts, json.string)),
    #("muda", json.array(u.muda, json.string)),
    #("density", json.float(float_round2(density(u)))),
    #("entropy_bits", json.float(float_round2(entropy_bits(u)))),
    #("introspection", json.array(introspect(u), json.string)),
  ])
}

/// Grammar summary for humans and other agents (served as shared state).
pub const grammar = "utterance  := header+ clause* tag*
header     := '@perf' PERF | '@from' AGENT '/' LAYER '@to' AGENT | '@re' ID | '@ooda' PHASE | '@conf' FLOAT | '@cost' INT | '@by' ISO8601
clause     := modal atoms ('⇐' atoms)?
modal      := 'K(' AGENT '):' | 'B(' AGENT '):' | 'I(' AGENT '):' | 'O(' AGENT '):' | 'G:' | '∴'
atoms      := atom ('∧' atom)*
atom       := IDENT ('(' value (',' value)* ')')? ('=' value)?
value      := IDENT | NUMBER | STRING
tag        := '#aspects' INT(,INT)* | '#ca' CA(,CA)* | '#onto' CONCEPT(|CONCEPT)* | '#muda' MUDA(,MUDA)*
PERF       := INFORM|REQUEST|PROPOSE|ACCEPT|REJECT|QUERY|CONFIRM|COMMIT|ASSERT|RETRACT|HYPOTHESIZE|ANDON
comment    := ';' to end of line"
