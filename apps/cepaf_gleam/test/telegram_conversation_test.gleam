import cepaf_gleam/harness/telegram_conversation as c
import gleam/list
import gleam/string
import gleeunit/should

fn scope() { c.Scope(123, -456, 789) }
fn empty() { c.Context(scope(), []) }
fn turn(id: Int) { c.Turn(id, "Question", "Answer") }

pub fn all_three_identity_dimensions_partition_context_test() {
  let scopes = [scope(), c.Scope(124, -456, 789), c.Scope(123, -457, 789), c.Scope(123, -456, 790)]
  let keys = list.map(scopes, fn(s) { let assert Ok(key) = c.context_key(s) key })
  list.length(list.unique(keys)) |> should.equal(4)
  let assert Ok(raw) = c.encode_context(empty())
  list.each(list.drop(scopes, 1), fn(other) {
    c.decode_context(raw, other) |> should.equal(Error("conversation_scope_or_state_mismatch"))
  })
}

pub fn invalid_scope_is_refused_test() {
  list.each([c.Scope(0, 1, 1), c.Scope(1, 0, 1), c.Scope(1, 1, 0), c.Scope(-1, 1, 1)], fn(s) {
    c.context_key(s) |> should.equal(Error("invalid_conversation_scope"))
    c.encode_context(c.Context(s, [])) |> should.equal(Error("invalid_conversation_state"))
  })
}

pub fn complete_turn_roundtrip_and_idempotent_replay_test() {
  let assert Ok(first) = c.append(empty(), turn(11))
  c.append(first, turn(11)) |> should.equal(Ok(first))
  let assert Ok(raw) = c.encode_context(first)
  c.decode_context(raw, scope()) |> should.equal(Ok(first))
  c.append(first, c.Turn(11, "Changed", "Answer")) |> should.equal(Error("conversation_update_collision"))
}

pub fn history_has_count_and_byte_limits_test() {
  let context = list.fold([1,2,3,4,5,6,7,8,9,10], empty(), fn(acc, id) {
    let assert Ok(next) = c.append(acc, turn(id))
    next
  })
  list.map(context.turns, fn(t) { let assert c.Turn(id, ..) = t id }) |> should.equal([3,4,5,6,7,8,9,10])
  let big = list.fold([1,2,3], empty(), fn(acc, id) {
    let assert Ok(next) = c.append(acc, c.Turn(id, string.repeat("q", 4096), string.repeat("a", 8192)))
    next
  })
  list.length(big.turns) |> should.equal(2)
  let assert Ok(raw) = c.encode_context(big)
  assert string.byte_size(raw) <= c.max_context_json_bytes
}

pub fn malformed_or_partial_turn_never_changes_context_test() {
  list.each([
    c.Turn(1, "", "reply"), c.Turn(1, "prompt", ""), c.Turn(-1, "p", "r"),
    c.Turn(1, string.repeat("x",4097), "reply"),
    c.Turn(1, "prompt", string.repeat("x",8193)),
    c.Turn(1, "prompt\u{0}", "reply"), c.Turn(1, "prompt", "reply\r"),
  ], fn(t) {
    c.append(empty(), t) |> should.equal(Error("invalid_conversation_state"))
    empty().turns |> should.equal([])
  })
}

pub fn corrupt_context_and_oversize_json_refused_test() {
  let assert Ok(raw) = c.encode_context(c.Context(scope(), [turn(1)]))
  c.decode_context(string.replace(raw, "uos.telegram.conversation.v1", "other"), scope())
    |> should.equal(Error("conversation_scope_or_state_mismatch"))
  c.decode_context(string.repeat("x",65537), scope()) |> should.equal(Error("invalid_conversation_bounds"))
  c.decode_context("{}", scope()) |> should.equal(Error("invalid_conversation_json"))
  c.encode_context(c.Context(scope(), [turn(1), turn(1)])) |> should.equal(Error("invalid_conversation_state"))
}

pub fn json_escape_expansion_remains_within_storage_bound_test() {
  let assert Ok(context) = c.append(empty(), c.Turn(1, string.repeat("\"",4096), string.repeat("\\",8192)))
  let assert Ok(raw) = c.encode_context(context)
  assert string.byte_size(raw) <= c.max_context_json_bytes
  c.decode_context(raw, scope()) |> should.equal(Ok(context))
}

pub fn daily_budget_reserves_before_completion_and_never_refunds_test() {
  let initial = c.DailyBudget(123, 20000, 0)
  let assert Ok(first) = c.reserve(initial, 123, 20000, 2)
  let assert Ok(second) = c.reserve(first, 123, 20000, 2)
  first.reserved_requests |> should.equal(1)
  second.reserved_requests |> should.equal(2)
  c.reserve(second, 123, 20000, 2) |> should.equal(Error("daily_request_budget_exhausted"))
  let assert Ok(raw) = c.encode_budget(second)
  c.decode_budget(raw, 123, 20000) |> should.equal(Ok(second))
}

pub fn budget_scope_limits_and_day_boundary_test() {
  c.utc_day(86399999) |> should.equal(Ok(0))
  c.utc_day(86400000) |> should.equal(Ok(1))
  c.utc_day(-1) |> should.equal(Error("invalid_budget_clock"))
  let b = c.DailyBudget(123, 20000, 1)
  list.each([0,1001], fn(limit) { c.reserve(b,123,20000,limit) |> should.equal(Error("invalid_budget_state")) })
  c.reserve(b,124,20000,2) |> should.equal(Error("invalid_budget_state"))
  c.reserve(b,123,20001,2) |> should.equal(Error("invalid_budget_state"))
  let assert Ok(raw) = c.encode_budget(b)
  c.decode_budget(raw,123,20001) |> should.equal(Error("budget_scope_or_state_mismatch"))
  c.decode_budget(string.repeat("x",1025),123,20000) |> should.equal(Error("invalid_budget_bounds"))
  c.encode_budget(c.DailyBudget(123,20000,-1)) |> should.equal(Error("invalid_budget_state"))
}

pub fn model_request_is_free_bounded_and_history_scoped_test() {
  let assert Ok(context) = c.append(empty(), turn(1))
  let assert Ok(req) = c.prepare_request(context, "What did I ask earlier?")
  req.model |> should.equal("openrouter/free")
  req.max_tokens |> should.equal(512)
  string.contains(req.user, "Question") |> should.equal(True)
  string.contains(req.system, "cannot execute commands") |> should.equal(True)
  string.contains(req.user, "bot_id") |> should.equal(False)
}

pub fn model_input_policy_and_empty_prompt_refused_test() {
  c.prepare_request(empty(), "") |> should.equal(Error("invalid_conversation_request"))
  c.prepare_request(empty(), "/home/private/secret.txt") |> should.equal(Error("model_input_policy_refused"))
}

const mini_id = "0123456789abcdef0123456789abcdef"
fn mini() { c.MiniTurn(mini_id, "Mini question", "Mini answer") }
pub fn legacy_v1_encoding_bytes_unchanged_test() {
  let assert Ok(raw) = c.encode_context(c.Context(scope(),[turn(1)]))
  raw |> should.equal("{\"schema\":\"uos.telegram.conversation.v1\",\"bot_id\":123,\"chat_id\":-456,\"user_id\":789,\"turns\":[{\"update_id\":1,\"prompt\":\"Question\",\"reply\":\"Answer\"}]}")
}
pub fn mixed_identity_roundtrip_and_replay_test() {
  let assert Ok(a)=c.append(empty(),turn(1))
  let assert Ok(b)=c.append(a,mini())
  let assert Ok(ctx)=c.append(b,turn(2))
  let assert Ok(raw)=c.encode_context(ctx)
  string.contains(raw,"uos.telegram.conversation.v2") |> should.be_true
  c.decode_context(raw,scope()) |> should.equal(Ok(ctx))
  c.append(ctx,mini()) |> should.equal(Ok(ctx))
  c.append(ctx,c.MiniTurn(mini_id,"changed","Mini answer")) |> should.be_error
  list.map(ctx.turns,c.turn_identity) |> should.equal(["telegram:1","mini:"<>mini_id,"telegram:2"])
}
pub fn mini_identity_and_text_bounds_test() {
  list.each(["",string.repeat("a",31),string.repeat("a",33),string.repeat("A",32),string.repeat("g",32)],fn(id) {
    c.append(empty(),c.MiniTurn(id,"p","r")) |> should.be_error
  })
  list.each([c.MiniTurn(mini_id,"","r"),c.MiniTurn(mini_id,"p",""),c.MiniTurn(mini_id,"p\u{0}","r")],fn(t) {
    c.append(empty(),t) |> should.be_error
  })
}
pub fn mixed_fifo_eviction_and_v1_downgrade_test() {
  let assert Ok(initial)=c.append(empty(),mini())
  let seven=list.fold([1,2,3,4,5,6,7],initial,fn(ctx,id) {let assert Ok(next)=c.append(ctx,turn(id)) next})
  list.length(seven.turns) |> should.equal(8)
  let assert Ok(before)=c.encode_context(seven)
  string.contains(before,"conversation.v2") |> should.be_true
  let assert Ok(eight)=c.append(seven,turn(8))
  list.map(eight.turns,c.turn_identity) |> should.equal(["telegram:1","telegram:2","telegram:3","telegram:4","telegram:5","telegram:6","telegram:7","telegram:8"])
  let assert Ok(after)=c.encode_context(eight)
  string.contains(after,"conversation.v1") |> should.be_true
}
pub fn v2_wrong_kind_ambiguous_and_legacy_schema_refused_test() {
  let assert Ok(raw)=c.encode_context(c.Context(scope(),[mini()]))
  list.each([
    string.replace(raw,"\"kind\":\"mini\"","\"kind\":\"other\""),
    string.replace(raw,"\"kind\":\"mini\"","\"kind\":\"telegram\""),
    string.replace(raw,"\"kind\":\"mini\"","\"kind\":\"mini\",\"update_id\":1"),
    string.replace(raw,"\"request_id\"","\"missing_id\""),
    string.replace(raw,"conversation.v2","conversation.v1"),
    string.replace(raw,mini_id,"bad"),
  ],fn(bad) {c.decode_context(bad,scope()) |> should.be_error})
}
pub fn v2_byte_limit_applies_to_unified_history_test() {
  let a=c.MiniTurn(mini_id,string.repeat("m",4096),string.repeat("r",8192))
  let b=c.Turn(1,string.repeat("t",4096),string.repeat("r",8192))
  let assert Ok(ctx)=c.append(c.Context(scope(),[a,b]),turn(2))
  ctx.turns |> should.equal([b,turn(2)])
  c.encode_context(c.Context(scope(),[mini(),mini()])) |> should.be_error
}
pub fn mixed_model_context_and_reset_serialization_test() {
  let ctx=c.Context(scope(),[mini(),turn(1)])
  let assert Ok(req)=c.prepare_request(ctx,"Continue")
  string.contains(req.user,"Mini question") |> should.be_true
  string.contains(req.user,"Question") |> should.be_true
  req.model |> should.equal("openrouter/free")
  let assert Ok(reset)=c.encode_context(c.Context(scope(),[]))
  string.contains(reset,"conversation.v1") |> should.be_true
  c.decode_context(reset,scope()) |> should.equal(Ok(empty()))
}
