//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/gateway/whatsapp</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ZENOH-005</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/gateway/telegram
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type Message {
  SendStatus(String)
  Stop
}

pub fn start(
  token: String,
  phone: String,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: token,
      chat_id: phone,
    )

  actor.new(state)
  |> actor.on_message(fn(state, msg) {
    case msg {
      SendStatus(text) -> {
        let _ = telegram.send_notification(state, "whatsapp", text)
        actor.continue(state)
      }
      Stop -> actor.stop()
    }
  })
  |> actor.start()
}
