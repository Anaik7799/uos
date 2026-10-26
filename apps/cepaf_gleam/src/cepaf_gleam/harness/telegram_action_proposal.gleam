//// Durable signable proposal data. Decoding or collecting receipts grants no authority.
import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_cancellation_record as recovery
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_store_codec as codec
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub opaque type Proposal {
  Proposal(request_id:String,intent:action.Intent,binding:action.Binding,
    target:action.Target,roster_digest:String,receipts:List(approval.Receipt))
}

pub fn new(request_id:String,intent:action.Intent,roster_digest:String)
  -> Result(Proposal,String) {
  use #(restored,binding,target) <- result.try(
    recovery.decode_intent_json(action.canonical_json(intent)))
  // A proposal collects approvals for a lease cancellation only; a verify
  // intent has its own packet path and is refused here by kind.
  case action.kind(restored)==action.CancelJobLease
    && request_id==ledger.make_request_id(binding.bot_id,binding.update_id)
    && string.byte_size(roster_digest)==64
    && list.all(string.to_graphemes(roster_digest),fn(c){
      string.contains("0123456789abcdef",c)}) {
    True -> Ok(Proposal(request_id,restored,binding,target,roster_digest,[]))
    False -> Error("invalid_action_proposal")
  }
}
pub fn request_id(p:Proposal) -> String { p.request_id }
pub fn intent(p:Proposal) -> action.Intent { p.intent }
pub fn binding(p:Proposal) -> action.Binding { p.binding }
pub fn target(p:Proposal) -> action.Target { p.target }
pub fn roster_digest(p:Proposal) -> String { p.roster_digest }
pub fn receipts(p:Proposal) -> List(approval.Receipt) { p.receipts }

/// Shape validation only. The service must cryptographically validate all
/// receipts against the current trusted roster before storing or using them.
pub fn with_receipts(p:Proposal,rs:List(approval.Receipt)) -> Result(Proposal,String) {
  case list.length(rs)<=4 && valid_receipts(rs,[]) {
    True -> Ok(Proposal(..p,receipts:rs))
    False -> Error("invalid_action_proposal")
  }
}
fn valid_receipts(rs:List(approval.Receipt),seen:List(approval.Role)) -> Bool {
  case rs {
    [] -> True
    [r,..rest] -> string.byte_size(r.token)>0 && string.byte_size(r.token)<=8192
      && !list.contains(seen,r.role) && valid_receipts(rest,[r.role,..seen])
  }
}
pub fn extends(previous:Proposal,next:Proposal) -> Bool {
  previous.request_id==next.request_id
  && action.canonical_json(previous.intent)==action.canonical_json(next.intent)
  && previous.roster_digest==next.roster_digest
  && list.take(next.receipts,list.length(previous.receipts))==previous.receipts
}
pub fn encode(p:Proposal) -> String {
  json.array([
    json.string("uos.telegram.action-proposal.v1"),json.string(p.request_id),
    json.string(action.canonical_json(p.intent)),json.string(p.roster_digest),
    json.array(p.receipts,fn(r){json.array([
      json.string(approval.role_name(r.role)),json.string(r.token)],fn(x){x})})
  ],fn(x){x}) |> json.to_string
}
pub fn decode(raw:String) -> Result(Proposal,String) {
  case string.byte_size(raw)>0 && string.byte_size(raw)<=65536 {
    False -> Error("invalid_action_proposal")
    True -> case codec.parse_strict_json(raw) {
      Ok(codec.JsonArray([codec.JsonString("uos.telegram.action-proposal.v1"),
        codec.JsonString(id),codec.JsonString(text),codec.JsonString(roster),
        codec.JsonArray(rs)])) -> {
          use #(intent,_,_) <- result.try(recovery.decode_intent_json(text))
          use p <- result.try(new(id,intent,roster))
          use receipts <- result.try(list.try_map(rs,decode_receipt))
          with_receipts(p,receipts)
        }
      _ -> Error("invalid_action_proposal")
    }
  }
}
fn decode_receipt(value:codec.StrictJsonValue) -> Result(approval.Receipt,String) {
  case value {
    codec.JsonArray([codec.JsonString(role),codec.JsonString(token)]) -> {
      use role <- result.try(case role {
        "codex" -> Ok(approval.Codex)
        "agy" -> Ok(approval.Agy)
        "claude" -> Ok(approval.Claude)
        "operator" -> Ok(approval.Operator)
        _ -> Error("invalid_action_proposal")
      })
      Ok(approval.Receipt(role,token))
    }
    _ -> Error("invalid_action_proposal")
  }
}
