import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_conversation as conv
import gleam/int.{parse, to_string}
import gleam/list.{drop, length, map}
import gleam/result
import gleam/string.{byte_size, join, to_graphemes}

pub const max_reply_bytes = 32_768

pub type Reply {
  Reply(text: String, clear: Bool)
}

pub fn reply(raw: String, context: conv.Context) -> Result(Reply, String) {
  case conv.valid_context(context) {
    False -> Error("Invalid conversation context or scope.")
    True -> {
      use invocation <- result.try(
        commands.parse(raw)
        |> result.map_error(fn(_) { "Unknown or unsupported command." }),
      )
      dispatch(invocation.definition.canonical, invocation.args, context)
    }
  }
}

fn dispatch(
  canonical: String,
  args: String,
  context: conv.Context,
) -> Result(Reply, String) {
  case canonical {
    "/memory" -> handle_memory(args, context)
    "/messages" | "/history" -> handle_messages(args, context)
    _ -> Error("Unsupported command: " <> canonical)
  }
}

fn handle_memory(args: String, context: conv.Context) -> Result(Reply, String) {
  case args {
    "" -> {
      let count = length(context.turns)
      let max = conv.max_turns
      let text =
        "Memory status: "
        <> to_string(count)
        <> " of "
        <> to_string(max)
        <> " complete exchanges stored.\n"
        <> "This memory belongs to you in this chat with this bot.\n"
        <> "Usage: send /memory clear or /memory reset to clear stored history."
      finalize_reply(text, False)
    }
    "clear" | "reset" ->
      finalize_reply(
        "Your conversation history in this chat has been cleared.",
        True,
      )
    _ ->
      Error(
        "Unsupported /memory arguments. Usage: /memory, /memory clear, or /memory reset.",
      )
  }
}

fn handle_messages(
  args: String,
  context: conv.Context,
) -> Result(Reply, String) {
  use limit <- result.try(parse_limit(args))
  let total = length(context.turns)
  case total {
    0 ->
      finalize_reply(
        "No stored conversation history (0 of "
          <> to_string(conv.max_turns)
          <> " complete exchanges).",
        False,
      )
    _ -> {
      let drop_count = case total > limit {
        True -> total - limit
        False -> 0
      }
      let latest_turns = drop(context.turns, drop_count)
      let shown = length(latest_turns)
      let rendered_turns =
        map(latest_turns, fn(turn) {
          "You: " <> turn.prompt <> "\nAssistant: " <> turn.reply
        })
      let header =
        "History ("
        <> to_string(shown)
        <> " of "
        <> to_string(total)
        <> " stored exchanges):"
      let text = header <> "\n" <> join(rendered_turns, "\n\n")
      finalize_reply(text, False)
    }
  }
}

fn parse_limit(args: String) -> Result(Int, String) {
  case args {
    "" -> Ok(conv.max_turns)
    _ -> {
      let chars = to_graphemes(args)
      case valid_positive_ascii_digits(chars) {
        False ->
          Error(
            "Invalid history count: expected a single ASCII integer between 1 and "
            <> to_string(conv.max_turns)
            <> ".",
          )
        True -> {
          use n <- result.try(
            parse(args)
            |> result.map_error(fn(_) { "Invalid history count." }),
          )
          case n >= 1 && n <= conv.max_turns {
            True -> Ok(n)
            False ->
              Error(
                "History count out of bounds: must be between 1 and "
                <> to_string(conv.max_turns)
                <> ".",
              )
          }
        }
      }
    }
  }
}

fn valid_positive_ascii_digits(chars: List(String)) -> Bool {
  case chars {
    [] -> False
    ["0", ..] -> False
    [first, ..rest] -> is_ascii_digit(first) && all_ascii_digits(rest)
  }
}

fn all_ascii_digits(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    [c, ..rest] -> is_ascii_digit(c) && all_ascii_digits(rest)
  }
}

fn is_ascii_digit(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn finalize_reply(text: String, clear: Bool) -> Result(Reply, String) {
  case byte_size(text) <= max_reply_bytes {
    True -> Ok(Reply(text: text, clear: clear))
    False -> Error("Formatted reply exceeds maximum allowed byte size.")
  }
}
