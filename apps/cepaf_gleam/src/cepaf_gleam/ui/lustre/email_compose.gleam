//// [C3I-SIL6-MSTS] Email compose widget. STAMP: SC-GLM-UI-001, SC-NOTIFY

import gleam/option.{type Option, None, Some}

pub type EmailModel {
  EmailModel(to: String, subject: String, body: String, attachments: List(String),
    sending: Bool, sent: Bool, error: Option(String))
}

pub type EmailMsg {
  SetTo(String)
  SetSubject(String)
  SetBody(String)
  AddAttachment(String)
  SendEmail
  EmailSent
  ErrorReceived(String)
}

pub fn init() -> EmailModel {
  EmailModel(to: "", subject: "", body: "", attachments: [], sending: False, sent: False, error: None)
}

pub fn update(model: EmailModel, msg: EmailMsg) -> EmailModel {
  case msg {
    SetTo(v) -> EmailModel(..model, to: v)
    SetSubject(v) -> EmailModel(..model, subject: v)
    SetBody(v) -> EmailModel(..model, body: v)
    AddAttachment(path) -> EmailModel(..model, attachments: [path, ..model.attachments])
    SendEmail -> EmailModel(..model, sending: True)
    EmailSent -> EmailModel(..model, sending: False, sent: True)
    ErrorReceived(e) -> EmailModel(..model, error: Some(e), sending: False)
  }
}

pub fn is_valid(model: EmailModel) -> Bool {
  model.to != "" && model.subject != ""
}
