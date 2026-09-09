import cepaf_gleam/agui/events.{
  ReasoningEnd, ReasoningMessageContent, ReasoningStart, RunFinished, RunStarted,
  TextMessageContent, TextMessageEnd, TextMessageStart, ToolCallArgs, ToolCallEnd,
  ToolCallResult, ToolCallStart,
}
import cepaf_gleam/harness/agy_agent.{
  type AgentDecision, AgentIntent, process_with_agy,
}
import gleam/list
import gleam/string
import gleeunit/should

pub fn agy_agent_synthesis_test() {
  let intent =
    AgentIntent(
      intent_id: "test-agy-001",
      source: "telegram",
      user: "Avi",
      chat_id: "142270921",
      text: "Synthesize operational posture for all 10 fractal layers",
      timestamp_ms: 1788979000000,
    )

  let decision: AgentDecision = process_with_agy(intent)

  decision.intent_id |> should.equal("test-agy-001")
  decision.ooda_phase |> should.equal("Completed")
  decision.confidence |> should.equal(0.99)

  // Markdown validation
  decision.reply_markdown
  |> string.contains("AGY Sovereign Agent Synthesis")
  |> should.be_true
  decision.reply_markdown
  |> string.contains("Google DeepMind Antigravity")
  |> should.be_true
  decision.reply_markdown
  |> string.contains("@Avi")
  |> should.be_true
  decision.reply_markdown
  |> string.contains("c3i_nif:system_health")
  |> should.be_true
  decision.reply_markdown
  |> string.contains("c3i_nif:plan_status")
  |> should.be_true

  // Actions list validation
  decision.actions
  |> list.contains("agy_observe_intent")
  |> should.be_true
  decision.actions
  |> list.contains("nif_query_health")
  |> should.be_true
  decision.actions
  |> list.contains("emit_agui_32_events")
  |> should.be_true

  // AG-UI 32-Event stream validation
  let events = decision.agui_events
  events |> list.length |> should.equal(12)

  let event_types = list.map(events, fn(e) { e.event_type })
  event_types
  |> should.equal([
    RunStarted,
    ReasoningStart,
    ReasoningMessageContent,
    ReasoningEnd,
    ToolCallStart,
    ToolCallArgs,
    ToolCallEnd,
    ToolCallResult,
    TextMessageStart,
    TextMessageContent,
    TextMessageEnd,
    RunFinished,
  ])
}

pub fn agy_agent_anonymous_user_test() {
  let intent =
    AgentIntent(
      intent_id: "test-agy-002",
      source: "telegram",
      user: "",
      chat_id: "142270921",
      text: "hello",
      timestamp_ms: 1788979000000,
    )

  let decision: AgentDecision = process_with_agy(intent)
  decision.reply_markdown
  |> string.contains("Greetings, Operator!")
  |> should.be_true
}
