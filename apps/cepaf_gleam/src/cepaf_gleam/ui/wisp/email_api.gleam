// STAMP: SC-GLM-UI-001, SC-NOTIFY
import cepaf_gleam/ui/lustre/email_compose.{type EmailModel}
import gleam/json

pub fn compose_json(model: EmailModel) -> json.Json {
  json.object([
    #("to", json.string(model.to)),
    #("subject", json.string(model.subject)),
    #("body", json.string(model.body)),
    #("valid", json.bool(email_compose.is_valid(model))),
    #("sending", json.bool(model.sending)),
    #("sent", json.bool(model.sent)),
  ])
}
