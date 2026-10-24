import cepaf_gleam/harness/telegram_commands.{
  ControlledAction, ConversationModel, Definition,
  Information, InvalidInput, Invocation, ReadObservation, UnknownCommand,
} as commands
import gleam/list
import gleam/string

const exact_77_literals = [
  "/start", "/help", "/status", "/storage", "/dark", "/andon", "/zigvm",
  "/plan", "/sutra", "/zk", "/checklist", "/cockpit", "/approval",
  "/resuscitate", "/chaos", "/repro", "/merge", "/bisect", "/escalate",
  "/rotate-keys", "/mesh", "/migrate", "/adr", "/blast-radius", "/pacing",
  "/whatif", "/simulate", "/rack-cv", "/acoustic", "/rewind", "/postmortem",
  "/finops", "/budget", "/eco-schedule", "/radar", "/canvas", "/lockbox",
  "/export-audit", "/sidecar", "/voice-roll-call", "/babel", "/whiteboard",
  "/socratic", "/handover", "/pair-voice", "/exec-brief", "/commitments",
  "/acoustic-hud", "/retro", "/gameday", "/aspects", "/ecology", "/health",
  "/tasks", "/task", "/search", "/immune", "/fmea", "/ha", "/zenoh",
  "/inference", "/verify", "/verification", "/rete", "/km", "/wiki", "/nvme",
  "/doctor", "/ev", "/agy", "/board", "/peers", "/memory", "/messages",
  "/history", "/tool", "/action",
]

pub fn exact_77_unique_catalog_coverage_test() {
  let entries = commands.catalog()
  let literals = list.map(entries, fn(d) { d.literal })

  assert list.length(entries) == 77
  assert literals == exact_77_literals
  assert list.unique(literals) == literals
  assert !list.contains(literals, "/saplan")

  list.each(entries, fn(entry) {
    assert commands.parse(entry.literal)
      == Ok(Invocation(definition: entry, args: ""))

    let assert Ok(canonical_def) =
      list.find(entries, fn(candidate) { candidate.literal == entry.canonical })
    assert canonical_def.canonical == canonical_def.literal
    assert canonical_def.kind == entry.kind
  })
}

pub fn supported_aliases_and_saplan_test() {
  let expected_aliases = [
    #("/start", "/help", Information),
    #("/simulate", "/whatif", ConversationModel),
    #("/budget", "/finops", ReadObservation),
    #("/verification", "/verify", ControlledAction),
    #("/ev", "/doctor", ReadObservation),
    #("/tasks", "/plan", ReadObservation),
    #("/nvme", "/storage", ReadObservation),
    #("/history", "/messages", ReadObservation),
    #("/action", "/tool", ControlledAction),
    #("/saplan", "/plan", ReadObservation),
  ]

  list.each(expected_aliases, fn(item) {
    let #(alias_literal, canonical_literal, expected_kind) = item
    assert commands.parse(alias_literal <> " --check")
      == Ok(
        Invocation(
          definition: Definition(
            literal: alias_literal,
            canonical: canonical_literal,
            kind: expected_kind,
          ),
          args: "--check",
        ),
      )
  })

  // /health and /status remain distinct canonical read commands.
  assert commands.parse("/health")
    == Ok(
      Invocation(
        definition: Definition(
          literal: "/health",
          canonical: "/health",
          kind: ReadObservation,
        ),
        args: "",
      ),
    )
  assert commands.parse("/status")
    == Ok(
      Invocation(
        definition: Definition(
          literal: "/status",
          canonical: "/status",
          kind: ReadObservation,
        ),
        args: "",
      ),
    )
}

pub fn conservative_operator_and_model_kind_classification_test() {
  let required_controlled_actions = [
    "/andon", "/approval", "/resuscitate", "/chaos", "/repro", "/merge",
    "/bisect", "/escalate", "/rotate-keys", "/migrate", "/rewind", "/lockbox",
    "/eco-schedule", "/sidecar", "/pair-voice", "/commitments", "/gameday",
    "/tool", "/action", "/verify", "/verification", "/zigvm",
  ]

  list.each(required_controlled_actions, fn(literal) {
    let assert Ok(invocation) = commands.parse(literal)
    assert invocation.definition.kind == ControlledAction
  })

  let conversational_models = [
    "/sutra", "/adr", "/whatif", "/simulate", "/postmortem", "/canvas",
    "/babel", "/whiteboard", "/socratic", "/exec-brief", "/retro", "/aspects",
    "/fmea", "/inference",
  ]

  list.each(conversational_models, fn(literal) {
    let assert Ok(invocation) = commands.parse(literal)
    assert invocation.definition.kind == ConversationModel
  })
}

pub fn unknown_suffix_and_exact_case_test() {
  assert commands.parse("/help-extra") == Error(UnknownCommand("/help-extra"))
  assert commands.parse("/helps") == Error(UnknownCommand("/helps"))
  assert commands.parse("/help@cepaf_bot")
    == Error(UnknownCommand("/help@cepaf_bot"))
  assert commands.parse("/plan2 arg") == Error(UnknownCommand("/plan2"))
  assert commands.parse("/rotate_keys") == Error(UnknownCommand("/rotate_keys"))
  assert commands.parse("/HELP") == Error(UnknownCommand("/HELP"))
  assert commands.parse("/Start") == Error(UnknownCommand("/Start"))
  assert commands.parse("/SAPLAN") == Error(UnknownCommand("/SAPLAN"))

  assert commands.parse("") == Error(InvalidInput)
  assert commands.parse("   \t\n  ") == Error(InvalidInput)
  assert commands.parse("/") == Error(InvalidInput)
  assert commands.parse("help") == Error(InvalidInput)
}

pub fn whitespace_splitting_prevents_second_command_test() {
  let assert Ok(tab_split) = commands.parse("  \t /doctor\t--verbose  ")
  assert tab_split.definition.literal == "/doctor"
  assert tab_split.definition.canonical == "/doctor"
  assert tab_split.args == "--verbose"

  let assert Ok(newline_split) =
    commands.parse("\n/plan\n/chaos --destroy-everything\n")
  assert newline_split.definition.literal == "/plan"
  assert newline_split.definition.canonical == "/plan"
  assert newline_split.args == "/chaos --destroy-everything"
}

pub fn forbidden_embedded_nul_and_control_bytes_test() {
  assert commands.parse("/help\u{0000}") == Error(InvalidInput)
  assert commands.parse("/help arg\u{0000}tail") == Error(InvalidInput)
  assert commands.parse("\u{0000}/help") == Error(InvalidInput)
  assert commands.parse("/status\u{0007}") == Error(InvalidInput)
  assert commands.parse("/status\u{0008}") == Error(InvalidInput)
  assert commands.parse("/status\u{000b}") == Error(InvalidInput)
  assert commands.parse("/status\u{000c}") == Error(InvalidInput)
  assert commands.parse("/status\r\n") == Error(InvalidInput)
  assert commands.parse("/status \u{001b}[31mred") == Error(InvalidInput)
  assert commands.parse("/status \u{007f}") == Error(InvalidInput)
  assert commands.parse("/status \u{0085}") == Error(InvalidInput)
}

pub fn oversized_utf8_text_and_args_bounds_test() {
  let exact_2048_args = string.repeat("a", 2048)
  let assert Ok(valid_max_args) = commands.parse("/plan " <> exact_2048_args)
  assert string.byte_size(valid_max_args.args) == 2048

  let over_2049_args = string.repeat("a", 2049)
  assert commands.parse("/plan " <> over_2049_args) == Error(InvalidInput)

  // 1025 two-byte UTF-8 characters = 2050 bytes (> 2048 args limit).
  let multibyte_over_args = string.repeat("é", 1025)
  assert string.byte_size(multibyte_over_args) == 2050
  assert commands.parse("/plan " <> multibyte_over_args) == Error(InvalidInput)

  // Leading whitespace padding pushing total message past 4096 bytes.
  let over_4096_total = string.repeat(" ", 4092) <> "/help"
  assert string.byte_size(over_4096_total) == 4097
  assert commands.parse(over_4096_total) == Error(InvalidInput)

  // Multibyte UTF-8 command token exceeding 4096 bytes.
  let over_4096_utf8 = "/" <> string.repeat("🚀", 1025)
  assert string.byte_size(over_4096_utf8) == 4101
  assert commands.parse(over_4096_utf8) == Error(InvalidInput)
}

pub fn parameters_not_shell_executed_and_reference_replies_safe_test() {
  let hostile_args = "$(touch /tmp/pwned); rm -rf / | `id`"

  let assert Ok(zigvm_inv) = commands.parse("/zigvm " <> hostile_args)
  assert zigvm_inv.definition.kind == ControlledAction
  assert zigvm_inv.args == hostile_args
  assert commands.reference_reply(zigvm_inv) == Error(Nil)

  let assert Ok(tool_inv) = commands.parse("/tool " <> hostile_args)
  assert tool_inv.definition.kind == ControlledAction
  assert tool_inv.args == hostile_args
  assert commands.reference_reply(tool_inv) == Error(Nil)

  let assert Ok(help_inv) = commands.parse("/help " <> hostile_args)
  let assert Ok(start_inv) = commands.parse("/start " <> hostile_args)
  let assert Ok(cockpit_inv) = commands.parse("/cockpit " <> hostile_args)

  let assert Ok(help_reply) = commands.reference_reply(help_inv)
  let assert Ok(start_reply) = commands.reference_reply(start_inv)
  let assert Ok(cockpit_reply) = commands.reference_reply(cockpit_inv)

  assert help_reply == start_reply
  assert !string.contains(help_reply, hostile_args)
  assert !string.contains(help_reply, "/tmp/pwned")
  assert !string.contains(cockpit_reply, hostile_args)
  assert string.contains(cockpit_reply, "http://nas-1.tail55d152.ts.net:4100/")

  // Help reply includes all four Kind groups, all 77 literals, and adapter caveat.
  assert string.contains(help_reply, "Help and navigation:")
  assert string.contains(help_reply, "Status and information:")
  assert string.contains(help_reply, "Actions requiring authorization:")
  assert string.contains(help_reply, "Assistant features:")
  assert string.contains(help_reply, "Unavailable features")
  assert string.contains(help_reply, "does not mean every feature is ready")

  list.each(exact_77_literals, fn(literal) {
    assert string.contains(help_reply, literal)
  })

  // Non-reference commands never fabricate health or static replies.
  let non_reference = ["/status", "/health", "/doctor", "/plan", "/saplan", "/whatif"]
  list.each(non_reference, fn(literal) {
    let assert Ok(inv) = commands.parse(literal <> " " <> hostile_args)
    assert commands.reference_reply(inv) == Error(Nil)
  })
}
