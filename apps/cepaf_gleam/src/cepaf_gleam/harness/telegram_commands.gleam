//// Pure Telegram slash-command catalog, strict bounded parser, and static
//// reference replies.
////
//// Parsing classifies command syntax only and never authorizes or executes
//// side effects. Runtime availability depends on separately wired adapters.

import gleam/list
import gleam/string

pub const max_text_bytes = 4096

pub const max_args_bytes = 2048

pub const cockpit_url = "http://nas-1.tail55d152.ts.net:4100/"

pub type Kind {
  Information
  ReadObservation
  ControlledAction
  ConversationModel
}

pub type Definition {
  Definition(literal: String, canonical: String, kind: Kind)
}

pub type Invocation {
  Invocation(definition: Definition, args: String)
}

pub type ParseError {
  InvalidInput
  UnknownCommand(String)
}

const saplan_alias_definition = Definition(
  literal: "/saplan",
  canonical: "/plan",
  kind: ReadObservation,
)

/// Returns the exact 77-command catalog in canonical order.
/// Extra legacy alias `/saplan` is supported by `parse` without expanding
/// the 77-entry catalog.
pub fn catalog() -> List(Definition) {
  [
    Definition(literal: "/start", canonical: "/help", kind: Information),
    Definition(literal: "/help", canonical: "/help", kind: Information),
    Definition(literal: "/status", canonical: "/status", kind: ReadObservation),
    Definition(
      literal: "/storage",
      canonical: "/storage",
      kind: ReadObservation,
    ),
    Definition(literal: "/dark", canonical: "/dark", kind: ControlledAction),
    Definition(literal: "/andon", canonical: "/andon", kind: ControlledAction),
    Definition(literal: "/zigvm", canonical: "/zigvm", kind: ControlledAction),
    Definition(literal: "/plan", canonical: "/plan", kind: ReadObservation),
    Definition(literal: "/sutra", canonical: "/sutra", kind: ConversationModel),
    Definition(literal: "/zk", canonical: "/zk", kind: ReadObservation),
    Definition(
      literal: "/checklist",
      canonical: "/checklist",
      kind: ReadObservation,
    ),
    Definition(literal: "/cockpit", canonical: "/cockpit", kind: Information),
    Definition(
      literal: "/approval",
      canonical: "/approval",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/resuscitate",
      canonical: "/resuscitate",
      kind: ControlledAction,
    ),
    Definition(literal: "/chaos", canonical: "/chaos", kind: ControlledAction),
    Definition(literal: "/repro", canonical: "/repro", kind: ControlledAction),
    Definition(literal: "/merge", canonical: "/merge", kind: ControlledAction),
    Definition(literal: "/bisect", canonical: "/bisect", kind: ControlledAction),
    Definition(
      literal: "/escalate",
      canonical: "/escalate",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/rotate-keys",
      canonical: "/rotate-keys",
      kind: ControlledAction,
    ),
    Definition(literal: "/mesh", canonical: "/mesh", kind: ReadObservation),
    Definition(
      literal: "/migrate",
      canonical: "/migrate",
      kind: ControlledAction,
    ),
    Definition(literal: "/adr", canonical: "/adr", kind: ConversationModel),
    Definition(
      literal: "/blast-radius",
      canonical: "/blast-radius",
      kind: ReadObservation,
    ),
    Definition(literal: "/pacing", canonical: "/pacing", kind: ReadObservation),
    Definition(
      literal: "/whatif",
      canonical: "/whatif",
      kind: ConversationModel,
    ),
    Definition(
      literal: "/simulate",
      canonical: "/whatif",
      kind: ConversationModel,
    ),
    Definition(
      literal: "/rack-cv",
      canonical: "/rack-cv",
      kind: ReadObservation,
    ),
    Definition(
      literal: "/acoustic",
      canonical: "/acoustic",
      kind: ReadObservation,
    ),
    Definition(literal: "/rewind", canonical: "/rewind", kind: ControlledAction),
    Definition(
      literal: "/postmortem",
      canonical: "/postmortem",
      kind: ConversationModel,
    ),
    Definition(literal: "/finops", canonical: "/finops", kind: ReadObservation),
    Definition(literal: "/budget", canonical: "/finops", kind: ReadObservation),
    Definition(
      literal: "/eco-schedule",
      canonical: "/eco-schedule",
      kind: ControlledAction,
    ),
    Definition(literal: "/radar", canonical: "/radar", kind: ReadObservation),
    Definition(
      literal: "/canvas",
      canonical: "/canvas",
      kind: ConversationModel,
    ),
    Definition(
      literal: "/lockbox",
      canonical: "/lockbox",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/export-audit",
      canonical: "/export-audit",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/sidecar",
      canonical: "/sidecar",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/voice-roll-call",
      canonical: "/voice-roll-call",
      kind: ControlledAction,
    ),
    Definition(literal: "/babel", canonical: "/babel", kind: ConversationModel),
    Definition(
      literal: "/whiteboard",
      canonical: "/whiteboard",
      kind: ConversationModel,
    ),
    Definition(
      literal: "/socratic",
      canonical: "/socratic",
      kind: ConversationModel,
    ),
    Definition(
      literal: "/handover",
      canonical: "/handover",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/pair-voice",
      canonical: "/pair-voice",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/exec-brief",
      canonical: "/exec-brief",
      kind: ConversationModel,
    ),
    Definition(
      literal: "/commitments",
      canonical: "/commitments",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/acoustic-hud",
      canonical: "/acoustic-hud",
      kind: ReadObservation,
    ),
    Definition(literal: "/retro", canonical: "/retro", kind: ConversationModel),
    Definition(
      literal: "/gameday",
      canonical: "/gameday",
      kind: ControlledAction,
    ),
    Definition(
      literal: "/aspects",
      canonical: "/aspects",
      kind: ConversationModel,
    ),
    Definition(
      literal: "/ecology",
      canonical: "/ecology",
      kind: ReadObservation,
    ),
    Definition(literal: "/health", canonical: "/health", kind: ReadObservation),
    Definition(literal: "/tasks", canonical: "/plan", kind: ReadObservation),
    Definition(literal: "/task", canonical: "/task", kind: ReadObservation),
    Definition(literal: "/search", canonical: "/search", kind: ReadObservation),
    Definition(literal: "/immune", canonical: "/immune", kind: ReadObservation),
    Definition(literal: "/fmea", canonical: "/fmea", kind: ConversationModel),
    Definition(literal: "/ha", canonical: "/ha", kind: ReadObservation),
    Definition(literal: "/zenoh", canonical: "/zenoh", kind: ReadObservation),
    Definition(
      literal: "/inference",
      canonical: "/inference",
      kind: ConversationModel,
    ),
    Definition(literal: "/verify", canonical: "/verify", kind: ControlledAction),
    Definition(
      literal: "/verification",
      canonical: "/verify",
      kind: ControlledAction,
    ),
    Definition(literal: "/rete", canonical: "/rete", kind: ReadObservation),
    Definition(literal: "/km", canonical: "/km", kind: ReadObservation),
    Definition(literal: "/wiki", canonical: "/wiki", kind: ReadObservation),
    Definition(literal: "/nvme", canonical: "/storage", kind: ReadObservation),
    Definition(literal: "/doctor", canonical: "/doctor", kind: ReadObservation),
    Definition(literal: "/ev", canonical: "/doctor", kind: ReadObservation),
    Definition(literal: "/agy", canonical: "/agy", kind: ControlledAction),
    Definition(literal: "/board", canonical: "/board", kind: ReadObservation),
    Definition(literal: "/peers", canonical: "/peers", kind: ReadObservation),
    Definition(literal: "/memory", canonical: "/memory", kind: ReadObservation),
    Definition(
      literal: "/messages",
      canonical: "/messages",
      kind: ReadObservation,
    ),
    Definition(
      literal: "/history",
      canonical: "/messages",
      kind: ReadObservation,
    ),
    Definition(literal: "/tool", canonical: "/tool", kind: ControlledAction),
    Definition(literal: "/action", canonical: "/tool", kind: ControlledAction),
  ]
}

/// Strictly parses a slash command invocation from raw text.
///
/// - Enforces <= 4096 UTF-8 bytes total and <= 2048 UTF-8 bytes for `args`.
/// - Refuses NUL and control characters (allowing only space, tab, LF).
/// - Accepts leading/trailing whitespace and splits command token from args
///   on the first space, tab, or newline so `args` remains inert data.
/// - Matches exact literal case against the 77-command catalog plus `/saplan`.
pub fn parse(text: String) -> Result(Invocation, ParseError) {
  case
    string.byte_size(text) <= max_text_bytes
    && !has_forbidden_control_chars(text)
  {
    False -> Error(InvalidInput)
    True -> {
      let trimmed = trim_allowed_whitespace(text)
      case string.starts_with(trimmed, "/") && trimmed != "/" {
        False -> Error(InvalidInput)
        True -> {
          let #(literal, raw_args) =
            split_command_and_args(string.to_graphemes(trimmed), [])
          let args = trim_allowed_whitespace(raw_args)
          case
            string.byte_size(raw_args) <= max_args_bytes
            && string.byte_size(args) <= max_args_bytes
          {
            False -> Error(InvalidInput)
            True ->
              case lookup_definition(literal) {
                Ok(definition) ->
                  Ok(Invocation(definition: definition, args: args))
                Error(Nil) -> Error(UnknownCommand(literal))
              }
          }
        }
      }
    }
  }
}

/// Pure informational reply for `/start`, `/help`, and `/cockpit` only.
///
/// Never interpolates user arguments, never fabricates runtime health, and
/// explicitly notes that runtime command availability comes from wired
/// adapters rather than catalog membership alone.
pub fn reference_reply(invocation: Invocation) -> Result(String, Nil) {
  case invocation.definition.literal {
    "/start" | "/help" -> Ok(render_catalog_help())
    "/cockpit" ->
      Ok(
        "UOS Cockpit: "
        <> cockpit_url
        <> "\nOpen the cockpit to view current system status.",
      )
    _ -> Error(Nil)
  }
}

fn lookup_definition(literal: String) -> Result(Definition, Nil) {
  case literal {
    "/saplan" -> Ok(saplan_alias_definition)
    _ ->
      list.find(catalog(), fn(definition) { definition.literal == literal })
  }
}

fn has_forbidden_control_chars(text: String) -> Bool {
  text
  |> string.to_utf_codepoints
  |> list.any(fn(cp) {
    let code = string.utf_codepoint_to_int(cp)
    case code {
      9 | 10 -> False
      _ if code < 32 -> True
      127 -> True
      _ if code >= 128 && code <= 159 -> True
      _ -> False
    }
  })
}

fn is_allowed_whitespace(grapheme: String) -> Bool {
  case grapheme {
    " " | "\t" | "\n" -> True
    _ -> False
  }
}

fn drop_leading_whitespace(graphemes: List(String)) -> List(String) {
  case graphemes {
    [first, ..rest] ->
      case is_allowed_whitespace(first) {
        True -> drop_leading_whitespace(rest)
        False -> graphemes
      }
    [] -> []
  }
}

fn trim_allowed_whitespace(text: String) -> String {
  text
  |> string.to_graphemes
  |> drop_leading_whitespace
  |> list.reverse
  |> drop_leading_whitespace
  |> list.reverse
  |> string.join("")
}

fn split_command_and_args(
  graphemes: List(String),
  cmd_acc: List(String),
) -> #(String, String) {
  case graphemes {
    [] -> #(string.join(list.reverse(cmd_acc), ""), "")
    [first, ..rest] ->
      case is_allowed_whitespace(first) {
        True -> #(
          string.join(list.reverse(cmd_acc), ""),
          rest
            |> drop_leading_whitespace
            |> list.reverse
            |> drop_leading_whitespace
            |> list.reverse
            |> string.join(""),
        )
        False -> split_command_and_args(rest, [first, ..cmd_acc])
      }
  }
}

fn render_catalog_help() -> String {
  let entries = catalog()
  string.join(
    [
      "UOS Telegram commands",
      "Some commands are still being completed. Unavailable features return an explicit error; this list does not mean every feature is ready.",
      render_kind_section("Help and navigation", Information, entries),
      render_kind_section("Status and information", ReadObservation, entries),
      render_kind_section("Actions requiring authorization", ControlledAction, entries),
      render_kind_section("Assistant features", ConversationModel, entries),
    ],
    "\n\n",
  )
}

fn render_kind_section(
  heading: String,
  target_kind: Kind,
  entries: List(Definition),
) -> String {
  let formatted_entries =
    entries
    |> list.filter(fn(definition) { definition.kind == target_kind })
    |> list.map(format_definition_entry)
    |> string.join(", ")

  heading <> ": " <> formatted_entries
}

fn format_definition_entry(definition: Definition) -> String {
  case definition.literal == definition.canonical {
    True -> definition.literal
    False -> definition.literal <> " (-> " <> definition.canonical <> ")"
  }
}
