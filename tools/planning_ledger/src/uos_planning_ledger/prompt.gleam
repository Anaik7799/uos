import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/string

pub type Availability {
  VerbatimAvailable
  PartialOrTruncated
}

pub type Prompt {
  Prompt(label: String, text: String, availability: Availability)
}

type ParseState {
  ParseState(
    records_reversed: List(Prompt),
    label: Option(String),
    body_reversed: List(String),
    inside_text: Bool,
    fence: String,
    want_latest: Bool,
  )
}

/// Extract the labelled prompt records from the journal's fenced `text`
/// blocks. This is the Gleam interpretation of the preservation grammar that
/// was previously implemented by the now-guarded, inert differential oracle
/// `legacy/extract_prompt_sql.pl.oracle.txt`.
pub fn extract(archive: String) -> List(Prompt) {
  let assert Ok(label_pattern) =
    regexp.from_string(
      "^\\[(Prompt [0-9]+|Continuation [0-9]+(?: / Prompt [0-9]+)?|Post-handover Prompt [0-9]+|Post-handover context artifact)\\][[:space:]]*$",
    )

  archive
  |> string.split("\n")
  |> list.fold(ParseState([], None, [], False, "", False), fn(state, line) {
    process_line(state, line, label_pattern)
  })
  |> flush
  |> fn(state) { list.reverse(state.records_reversed) }
}

fn process_line(state: ParseState, line: String, label_pattern: regexp.Regexp) {
  let syntax = string.trim_end(line)
  let latest_heading =
    string.starts_with(line, "### 3.3 Latest cumulative user prompt, verbatim")
    || string.starts_with(
      line,
      "### 3.4 Latest cumulative user prompt, verbatim",
    )

  case state.inside_text, latest_heading, syntax {
    False, True, _ -> ParseState(..state, want_latest: True)
    False, False, "```text" -> enter_text_fence(state, "```")
    False, False, "~~~text" -> enter_text_fence(state, "~~~")
    True, False, closing if closing == state.fence ->
      state
      |> flush
      |> fn(flushed) {
        ParseState(
          ..flushed,
          inside_text: False,
          fence: "",
          label: None,
          body_reversed: [],
        )
      }
    True, False, _ -> process_text_line(state, line, label_pattern)
    _, _, _ -> state
  }
}

fn enter_text_fence(state: ParseState, fence: String) -> ParseState {
  let state = case state.want_latest {
    True ->
      state
      |> flush
      |> fn(flushed) {
        ParseState(
          ..flushed,
          label: Some("Latest cumulative user prompt"),
          want_latest: False,
        )
      }
    False -> state
  }

  ParseState(..state, inside_text: True, fence: fence)
}

fn process_text_line(
  state: ParseState,
  line: String,
  label_pattern: regexp.Regexp,
) -> ParseState {
  case regexp.scan(with: label_pattern, content: line) {
    [regexp.Match(_, [Some(label)])] ->
      state
      |> flush
      |> fn(flushed) {
        ParseState(..flushed, label: Some(label), body_reversed: [])
      }
    _ ->
      case state.label {
        Some(_) ->
          ParseState(..state, body_reversed: [line, ..state.body_reversed])
        None -> state
      }
  }
}

fn flush(state: ParseState) -> ParseState {
  case state.label {
    None -> state
    Some(label) -> {
      let text =
        state.body_reversed
        |> list.reverse
        |> list.drop_while(is_blank)
        |> list.reverse
        |> list.drop_while(is_blank)
        |> list.reverse
        |> string.join("\n")
        |> string.trim_end

      let records = case text {
        "" -> state.records_reversed
        text -> [
          Prompt(label, text, availability(text)),
          ..state.records_reversed
        ]
      }

      ParseState(
        ..state,
        records_reversed: records,
        label: None,
        body_reversed: [],
      )
    }
  }
}

fn is_blank(line: String) -> Bool {
  string.trim(line) == ""
}

fn availability(text: String) -> Availability {
  let lowercase = string.lowercase(text)
  let assert Ok(terminal_u) = regexp.from_string("\\bu$")
  case
    string.contains(lowercase, "truncat"),
    regexp.check(with: terminal_u, content: lowercase)
  {
    True, _ | _, True -> PartialOrTruncated
    False, False -> VerbatimAvailable
  }
}
