import gleam/list
import cepaf_gleam/harness/telegram_ingress_guard as g
import gleam/json
import gleam/string
import gleeunit/should

fn allow() {
  g.Allowlist(123, [#(1001, 501), #(-1001, 501)])
}

fn payload(
  uid: Int,
  mid: Int,
  chat: Int,
  user: Int,
  kind: String,
  bot: Bool,
  text: String,
) {
  json.object([
    #("update_id", json.int(uid)),
    #(
      "message",
      json.object([
        #("message_id", json.int(mid)),
        #(
          "chat",
          json.object([#("id", json.int(chat)), #("type", json.string(kind))]),
        ),
        #(
          "from",
          json.object([#("id", json.int(user)), #("is_bot", json.bool(bot))]),
        ),
        #("text", json.string(text)),
      ]),
    ),
  ])
  |> json.to_string
}

fn accepted(v: g.IngressVerdict) {
  case v {
    g.AcceptedEnvelope(..) -> True
    _ -> False
  }
}

pub fn valid_pair_test() {
  g.evaluate_update(
    payload(100, 10, 1001, 501, "private", False, "/doctor"),
    allow(),
  )
  |> accepted
  |> should.be_true
}

pub fn username_is_not_authority_test() {
  g.evaluate_update(
    payload(100, 10, 1001, 999, "private", False, "/doctor"),
    allow(),
  )
  |> accepted
  |> should.be_false
}

pub fn group_negative_id_test() {
  g.evaluate_update(
    payload(100, 10, -1001, 501, "supergroup", False, "/doctor"),
    allow(),
  )
  |> accepted
  |> should.be_true
}

pub fn channel_and_unknown_type_test() {
  g.evaluate_update(
    payload(100, 10, 1001, 501, "channel", False, "/doctor"),
    allow(),
  )
  |> accepted
  |> should.be_false
  g.evaluate_update(
    payload(100, 10, 1001, 501, "invented", False, "/doctor"),
    allow(),
  )
  |> accepted
  |> should.be_false
}

pub fn bot_sender_test() {
  g.evaluate_update(
    payload(100, 10, 1001, 501, "private", True, "/doctor"),
    allow(),
  )
  |> accepted
  |> should.be_false
}

pub fn missing_security_fields_test() {
  let raw =
    "{\"update_id\":100,\"message\":{\"message_id\":10,\"chat\":{\"id\":1001},\"from\":{\"id\":501},\"text\":\"/doctor\"}}"
  g.evaluate_update(raw, allow()) |> accepted |> should.be_false
}

pub fn sender_chat_test() {
  let raw =
    "{\"update_id\":100,\"message\":{\"message_id\":10,\"chat\":{\"id\":1001,\"type\":\"private\"},\"from\":{\"id\":501,\"is_bot\":false},\"sender_chat\":null,\"text\":\"/doctor\"}}"
  g.evaluate_update(raw, allow()) |> accepted |> should.be_false
}

pub fn channel_post_test() {
  g.evaluate_update("{\"update_id\":100,\"channel_post\":{}}", allow())
  |> accepted
  |> should.be_false
}

pub fn invalid_ids_test() {
  g.evaluate_update(
    payload(-1, 0, 0, -3, "private", False, "/doctor"),
    g.Allowlist(0, [#(0, -3)]),
  )
  |> accepted
  |> should.be_false
  g.evaluate_update(
    payload(100, 0, 1001, 501, "private", False, "/doctor"),
    allow(),
  )
  |> accepted
  |> should.be_false
}

pub fn id_boundaries_test() {
  g.valid_update_id(0) |> should.be_true
  g.valid_update_id(g.max_update_id) |> should.be_true
  g.valid_update_id(g.max_update_id + 1) |> should.be_false
  g.valid_positive_id(g.max_identity) |> should.be_true
  g.valid_positive_id(g.max_identity + 1) |> should.be_false
  g.valid_chat_id(0 - g.max_identity) |> should.be_true
  g.valid_chat_id(0) |> should.be_false
}

pub fn text_boundaries_test() {
  g.evaluate_update(
    payload(100, 10, 1001, 501, "private", False, string.repeat("x", 4096)),
    allow(),
  )
  |> accepted
  |> should.be_true
  g.evaluate_update(
    payload(100, 10, 1001, 501, "private", False, string.repeat("x", 4097)),
    allow(),
  )
  |> accepted
  |> should.be_false
  g.evaluate_update(payload(100, 10, 1001, 501, "private", False, " "), allow())
  |> accepted
  |> should.be_false
}

pub fn malformed_has_no_private_leak_test() {
  let verdict = g.evaluate_update("{CANARY_PRIVATE", allow())
  string.inspect(verdict)
  |> string.contains("CANARY_PRIVATE")
  |> should.be_false
}

pub fn oversized_payload_test() {
  g.evaluate_update(string.repeat("x", 65_537), allow())
  |> should.equal(g.UnidentifiedRejection("payload_bound"))
}

pub fn empty_object_whitespace_test() {
  g.classify_directive("/tool query_doctor { \n\t }")
  |> should.equal(g.DirectReadTool("query_doctor"))
  g.classify_directive("/doctor")
  |> should.equal(g.DirectReadTool("query_doctor"))
}

pub fn strict_args_and_truthful_denial_test() {
  case g.classify_directive("/tool query_doctor {\"path\":\"/etc\"}") {
    g.DeniedMutation(..) -> Nil
    _ -> panic as "nonempty object accepted"
  }
  case g.classify_directive("/tool query_saplan []") {
    g.DeniedMutation(..) -> Nil
    _ -> panic as "array accepted"
  }
  case g.classify_directive("/approval approve") {
    g.DeniedMutation(_, reason) ->
      string.contains(reason, "Usage:") |> should.be_true
    _ -> panic as "approval allowed"
  }
}

pub fn rejection_fingerprint_test() {
  let a =
    g.evaluate_update(
      payload(100, 10, 1001, 999, "private", False, "a"),
      allow(),
    )
  let b =
    g.evaluate_update(
      payload(100, 10, 1001, 999, "private", False, "b"),
      allow(),
    )
  case a, b {
    g.RejectedUpdate(100, 123, hash_a, _), g.RejectedUpdate(100, 123, hash_b, _)
    -> {
      guard_hash(hash_a)
      { hash_a == hash_b } |> should.be_false
    }
    _, _ -> panic as "missing authenticated tombstone identity"
  }
}

fn guard_hash(hash: String) {
  g.valid_digest(hash) |> should.be_true
}

pub fn task_read_is_scoped_and_validated_at_ingress_test() {
  g.classify_directive("/task lease-e2e-01") |> should.equal(g.PreservedDirective("/task", ["lease-e2e-01"]))
  let assert g.DeniedMutation("/task", _) = g.classify_directive("/task")
  let assert g.DeniedMutation("/task", _) = g.classify_directive("/task other task")
  let assert g.DeniedMutation("/task", _) = g.classify_directive("/task x;DROP")
  let assert g.DeniedMutation("/task", _) = g.classify_directive("/task plan:task")
}

pub fn tool_action_alias_and_scoped_task_test() {
  g.classify_directive("/action\tquery_doctor\t{}")
    |> should.equal(g.DirectReadTool("query_doctor"))
  g.classify_directive("/tool query_saplan\n{}")
    |> should.equal(g.DirectReadTool("query_saplan"))
  g.classify_directive("/action query_task {\"task_id\":\"LEASE_1\"}")
    |> should.equal(g.PreservedDirective("/task", ["LEASE_1"]))
  g.classify_directive("/tool")
    |> should.equal(g.PreservedDirective("/tool_help", []))
  g.classify_directive("/action help")
    |> should.equal(g.PreservedDirective("/tool_help", []))
}
pub fn tool_foreign_scope_and_mutations_refused_test() {
  let inputs = [
    "/tool query_task {\"task_id\":\"LEASE_1\",\"plan\":\"foreign\"}",
    "/action query_task {\"task_id\":\"LEASE_1\",\"authority\":\"admin\"}",
    "/tool rotate_keys {}",
    "/action invoke_zigvm {}",
  ]
  list.each(inputs, fn(input) {
    case g.classify_directive(input) {
      g.DeniedMutation(..) -> Nil
      _ -> panic as "unsafe tool accepted"
    }
  })
}

pub fn system_status_fixed_scope_test() {
  g.classify_directive("/status") |> should.equal(g.DirectReadTool("query_system_health"))
  g.classify_directive("/health") |> should.equal(g.DirectReadTool("query_system_health"))
  g.classify_directive("/health {}") |> should.equal(g.DirectReadTool("query_system_health"))
  g.classify_directive("/action query_system_health {}") |> should.equal(g.DirectReadTool("query_system_health"))
  case g.classify_directive("/status {\"url\":\"http://evil/\"}") {
    g.DeniedMutation(..) -> Nil
    _ -> panic as "status scope override accepted"
  }
}

pub fn health_command_fixed_scope_and_refusal_test() {
  g.classify_directive("/health")
  |> should.equal(g.DirectReadTool("query_system_health"))
  g.classify_directive("/health { \n\t }")
  |> should.equal(g.DirectReadTool("query_system_health"))
  list.each(
    [
      "/health {\"url\":\"http://evil/\"}",
      "/health {\"host\":\"evil\"}",
      "/health check",
    ],
    fn(input) {
      let assert g.DeniedMutation("query_system_health", reason) =
        g.classify_directive(input)
      string.contains(reason, "Read arguments must be absent or an empty JSON object.")
      |> should.be_true
    },
  )
}

pub fn kernel_version_fixed_scope_test() {
  list.each(["/zigvm", "/zigvm version", "/tool query_zigvm_version {}", "/action query_zigvm_version"],
    fn(input) { g.classify_directive(input) |> should.equal(g.DirectReadTool("query_zigvm_version")) })
  list.each(["/zigvm eval x", "/zigvm version --path=x", "/tool query_zigvm_version {\"path\":\"evil\"}"],
    fn(input) { let assert g.DeniedMutation(..) = g.classify_directive(input) })
}


pub fn coordination_scope_at_ingress_test() {
  g.classify_directive("/peers") |> should.equal(g.DirectReadTool("query_peers"))
  g.classify_directive("/board") |> should.equal(g.DirectReadTool("query_board"))
  g.classify_directive("/tool query_peers {}") |> should.equal(g.DirectReadTool("query_peers"))
  g.classify_directive("/action query_board {}") |> should.equal(g.DirectReadTool("query_board"))
  list.each(["/peers private","/board send x","/tool query_peers {\"path\":\"evil\"}"], fn(input) {
    let assert g.DeniedMutation(..) = g.classify_directive(input)
  })
}

pub fn approval_status_ingress_test() {
 g.classify_directive("/approval") |> should.equal(g.PreservedDirective("/approval",[]))
 g.classify_directive("/approval list") |> should.equal(g.PreservedDirective("/approval",[]))
 g.classify_directive("/approval tg-333444-10") |> should.equal(g.PreservedDirective("/approval",["tg-333444-10"]))
 list.each(["/approval approve","/approval submit token","/approval ../file","/approval tg-1;DROP"],fn(text){let assert g.DeniedMutation(_,_) = g.classify_directive(text) Nil})
}

pub fn approval_propose_and_submit_ingress_test() {
 g.classify_directive("/approval propose tg-333444-10") |> should.equal(g.PreservedDirective("/approval_manage",["propose","tg-333444-10"]))
 g.classify_directive("/approval submit tg-333444-10 codex public.jwt.signature") |> should.equal(g.PreservedDirective("/approval_manage",["submit","tg-333444-10","codex","public.jwt.signature"]))
 list.each(["/approval propose ../x","/approval submit tg-1 admin token","/approval submit tg-1 codex token extra","/approval tg-"],fn(t){let assert g.DeniedMutation(_,_) = g.classify_directive(t) Nil})
}

pub fn approval_withdrawal_route_is_exact_test() {
  g.classify_directive("/approval withdraw tg-333444-10") |> should.equal(g.PreservedDirective("/approval_manage",["withdraw","tg-333444-10"]))
}

pub fn fmea_scoped_ingress_test() {
  list.each(["/fmea","/fmea {}","/tool query_fmea {}","/action query_fmea"],fn(t){
    g.classify_directive(t) |> should.equal(g.DirectReadTool("query_fmea"))
  })
  list.each(["/fmea TASK","/tool query_fmea {\"task_id\":\"TASK\"}"],fn(t){
    g.classify_directive(t) |> should.equal(g.PreservedDirective("/fmea",["TASK"]))
  })
  list.each(["/fmea TASK EXTRA","/fmea {\"path\":\"private\"}",
    "/tool query_fmea {\"task_id\":\"TASK\",\"plan_id\":\"foreign\"}"],fn(t){
      let assert g.DeniedMutation(_,_) = g.classify_directive(t) Nil
  })
}
