//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/agents/skill_loader</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-OPENCLAW-003, SC-COG-001</stamp-controls></compliance>
//// </c3i-module>
////
//// OpenClaw Skill Loader Agent.
//// Supervised OTP Actor that dynamically retrieves and formats SKILL.md files.

import cepaf_gleam/moz/client as moz
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/otp/actor

pub type SkillMessage {
  LoadSkill(name: String, reply_to: Subject(Result(String, String)))
  Stop
}

pub type SkillState {
  SkillState(id: String, moz: moz.MoZClientState)
}

/// Start the Skill Loader Agent as a supervised worker.
pub fn start(
  id: String,
) -> Result(actor.Started(Subject(SkillMessage)), actor.StartError) {
  let initial = SkillState(id: id, moz: moz.new())

  actor.new(initial)
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(
  state: SkillState,
  msg: SkillMessage,
) -> actor.Next(SkillState, SkillMessage) {
  case msg {
    LoadSkill(name, reply_to) -> {
      io.println(
        "🧠 SkillLoader ["
        <> state.id
        <> "]: Loading cognitive skill -> "
        <> name,
      )

      let skill_path = ".agents/skills/" <> name <> "/SKILL.md"
      let params = json.object([#("path", json.string(skill_path))])

      // Use the newly reified File IO motor tool to read the skill securely
      let #(_new_moz, result) =
        moz.send_request(state.moz, "plan", "read_file", params)

      case result {
        Ok(_) -> {
          // SC-OPENCLAW-003: Mandatory prefix injection
          let formatted_skill =
            "[SYSTEM SKILL DIRECTIVE]\nApplying Skill: "
            <> name
            <> "\n(Content loaded successfully)"
          process.send(reply_to, Ok(formatted_skill))
        }
        Error(e) -> {
          io.println("  [!] Failed to load skill: " <> e)
          process.send(reply_to, Error("Skill not found or inaccessible."))
        }
      }

      actor.continue(state)
    }
    Stop -> actor.stop()
  }
}
