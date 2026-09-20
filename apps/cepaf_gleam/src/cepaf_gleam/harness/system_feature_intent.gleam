import cepaf_gleam/harness/system_features as features
import cepaf_gleam/harness/value
import gleam/int
import gleam/json
import gleam/list
import gleam/result

pub type Intent {
  CatalogRead(String, Int)
  ObservationsRead(String, String, Int)
}

pub type Decision {
  Decision(
    intent: String,
    operation: String,
    catalog_sha256: String,
    ledger_sha256: String,
    offset: Int,
    effects: List(String),
  )
}

fn arguments(arguments: value.Value) -> Result(Nil, String) {
  case arguments {
    value.Object(fields) -> {
      let keys = list.map(fields, fn(field) { field.0 })
      case
        list.length(fields) == 4
        && list.length(list.unique(keys)) == 4
        && list.all(
          ["intent", "catalog_sha256", "ledger_sha256", "offset"],
          fn(key) { list.contains(keys, key) },
        )
      {
        True -> Ok(Nil)
        False -> Error("feature_intent_exact_arguments")
      }
    }
    _ -> Error("feature_intent_exact_arguments")
  }
}

fn digest(arguments: value.Value, key: String) -> Result(String, String) {
  case value.get(arguments, key) {
    Ok(value.Text(digest)) ->
      case features.valid_digest(digest) {
        True -> Ok(digest)
        False -> Error("feature_intent_digest:" <> key)
      }
    _ -> Error("feature_intent_digest:" <> key)
  }
}

fn offset(arguments: value.Value) -> Result(Int, String) {
  case value.get(arguments, "offset") {
    Ok(value.Text(raw)) -> {
      use parsed <- result.try(
        int.parse(raw) |> result.replace_error("feature_intent_offset"),
      )
      case parsed >= 0 && parsed <= 128 && int.to_string(parsed) == raw {
        True -> Ok(parsed)
        False -> Error("feature_intent_offset")
      }
    }
    _ -> Error("feature_intent_offset")
  }
}

pub fn decide(args: value.Value) -> Result(Decision, String) {
  use _ <- result.try(arguments(args))
  use intent <- result.try(case value.get(args, "intent") {
    Ok(value.Text(name)) -> Ok(name)
    _ -> Error("feature_intent_name")
  })
  use catalog <- result.try(digest(args, "catalog_sha256"))
  use ledger <- result.try(digest(args, "ledger_sha256"))
  use position <- result.try(offset(args))
  case intent {
    "catalog_read" ->
      Ok(
        Decision(
          intent,
          "harness_system_feature_catalog",
          catalog,
          ledger,
          position,
          [],
        ),
      )
    "observations_read" ->
      Ok(
        Decision(
          intent,
          "harness_system_feature_observations",
          catalog,
          ledger,
          position,
          [],
        ),
      )
    _ -> Error("feature_intent_unknown_or_denied")
  }
}

pub fn encode(decision: Decision) -> json.Json {
  let Decision(intent, operation, catalog, ledger, position, effects) = decision
  json.object([
    #("schema", json.string("uos.system-feature-intent-decision.v1")),
    #("intent", json.string(intent)),
    #("operation", json.string(operation)),
    #("catalog_sha256", json.string(catalog)),
    #("ledger_sha256", json.string(ledger)),
    #("offset", json.int(position)),
    #("effects", json.array(effects, json.string)),
    #("effect_authority", json.bool(False)),
    #("system_admission", json.bool(False)),
  ])
}

pub fn combine(left: Decision, right: Decision) -> Result(Decision, String) {
  case left == right {
    True -> Ok(left)
    False -> Error("feature_intent_conflict")
  }
}

pub fn laws() -> List(String) {
  [
    "identity",
    "deny-dominance",
    "no-authority-amplification",
    "replay-idempotence",
    "conflicting-replay-refusal",
  ]
}
