import cepaf_gleam/harness/telegram_conversation.{type Scope, type Turn, Context, Scope, Turn}
import cepaf_gleam/harness/telegram_memory_command.{Reply, reply}
import gleam/string.{byte_size}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn valid_scope() -> Scope {
  Scope(bot_id: 333444, chat_id: 100, user_id: 200)
}

fn sample_turns() -> List(Turn) {
  [
    Turn(update_id: 1, prompt: "first question", reply: "first answer"),
    Turn(update_id: 2, prompt: "second question", reply: "second answer"),
    Turn(update_id: 3, prompt: "third question", reply: "third answer"),
    Turn(update_id: 4, prompt: "fourth question", reply: "fourth answer"),
  ]
}

pub fn memory_count_and_guidance_test() {
  let empty_ctx = Context(scope: valid_scope(), turns: [])
  let assert Ok(Reply(text: empty_text, clear: False)) =
    reply("/memory", empty_ctx)
  should.equal(
    empty_text,
    "Memory status: 0 of 8 complete exchanges stored.\n"
      <> "This memory belongs to you in this chat with this bot.\n"
      <> "Usage: send /memory clear or /memory reset to clear stored history.",
  )

  let populated_ctx = Context(scope: valid_scope(), turns: sample_turns())
  let assert Ok(Reply(text: pop_text, clear: False)) =
    reply("/memory", populated_ctx)
  should.equal(
    pop_text,
    "Memory status: 4 of 8 complete exchanges stored.\n"
      <> "This memory belongs to you in this chat with this bot.\n"
      <> "Usage: send /memory clear or /memory reset to clear stored history.",
  )
}

pub fn memory_clear_and_reset_test() {
  let ctx = Context(scope: valid_scope(), turns: sample_turns())
  let expected =
    Ok(Reply(
      text: "Your conversation history in this chat has been cleared.",
      clear: True,
    ))

  should.equal(reply("/memory clear", ctx), expected)
  should.equal(reply("/memory reset", ctx), expected)
  // Context turns remain untouched (pure function, no state mutation)
  should.equal(ctx.turns, sample_turns())
}

pub fn command_aliases_history_and_messages_test() {
  let ctx = Context(scope: valid_scope(), turns: sample_turns())
  let from_messages = reply("/messages 2", ctx)
  let from_history = reply("/history 2", ctx)

  should.be_ok(from_messages)
  should.equal(from_messages, from_history)
}

pub fn latest_n_chronological_ordering_test() {
  let ctx = Context(scope: valid_scope(), turns: sample_turns())
  let assert Ok(Reply(text: text, clear: False)) = reply("/history 2", ctx)

  should.equal(
    text,
    "History (2 of 4 stored exchanges):\n"
      <> "You: third question\nAssistant: third answer\n\n"
      <> "You: fourth question\nAssistant: fourth answer",
  )
}

pub fn invalid_argument_boundaries_test() {
  let ctx = Context(scope: valid_scope(), turns: sample_turns())

  should.be_error(reply("/history 0", ctx))
  should.be_error(reply("/history 9", ctx))
  should.be_error(reply("/history +1", ctx))
  should.be_error(reply("/history -1", ctx))
  should.be_error(reply("/history 01", ctx))
  should.be_error(reply("/history 1junk", ctx))
  should.be_error(reply("/history 1 2", ctx))
  should.be_error(reply("/memory unknown", ctx))
  should.be_error(reply("/memory clear now", ctx))
}

pub fn invalid_scope_and_context_test() {
  let invalid_scope_ctx =
    Context(
      scope: Scope(bot_id: 0, chat_id: 100, user_id: 200),
      turns: [],
    )
  should.be_error(reply("/memory", invalid_scope_ctx))
  should.be_error(reply("/history", invalid_scope_ctx))

  let nine_turns = [
    Turn(1, "p1", "r1"),
    Turn(2, "p2", "r2"),
    Turn(3, "p3", "r3"),
    Turn(4, "p4", "r4"),
    Turn(5, "p5", "r5"),
    Turn(6, "p6", "r6"),
    Turn(7, "p7", "r7"),
    Turn(8, "p8", "r8"),
    Turn(9, "p9", "r9"),
  ]
  let overfull_ctx = Context(scope: valid_scope(), turns: nine_turns)
  should.be_error(reply("/memory", overfull_ctx))
}

pub fn unicode_preservation_and_byte_bound_test() {
  let unicode_turns = [
    Turn(
      update_id: 10,
      prompt: "こんにちは 🌍 — café",
      reply: "Привет 🚀 — naïve résumé",
    ),
  ]
  let ctx = Context(scope: valid_scope(), turns: unicode_turns)
  let assert Ok(Reply(text: text, clear: False)) = reply("/messages 1", ctx)

  should.equal(
    text,
    "History (1 of 1 stored exchanges):\n"
      <> "You: こんにちは 🌍 — café\nAssistant: Привет 🚀 — naïve résumé",
  )
  should.equal(byte_size(text) <= 32_768, True)
}

pub fn unknown_command_rejected_test() {
  let ctx = Context(scope: valid_scope(), turns: sample_turns())

  should.be_error(reply("/unknown", ctx))
  should.be_error(reply("/start", ctx))
  should.be_error(reply("plain text", ctx))
}

pub fn empty_history_response_test() {
  let empty_ctx = Context(scope: valid_scope(), turns: [])
  let assert Ok(Reply(text: text, clear: False)) = reply("/history", empty_ctx)

  should.equal(
    text,
    "No stored conversation history (0 of 8 complete exchanges).",
  )
}
