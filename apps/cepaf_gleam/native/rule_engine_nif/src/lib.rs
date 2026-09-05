//! # Rule Engine NIF — RETE-UL for BEAM/Gleam
//!
//! Exposes the rust-rule-engine (RETE-UL, GRL syntax) as Erlang NIFs
//! callable from Gleam via @external(erlang, "rule_engine_nif", ...).
//!
//! STAMP: SC-OODA-003, SC-ALLIUM-001

use rust_rule_engine::{Facts, GRLParser, KnowledgeBase, RustRuleEngine, Value};
use rustler::NifResult;

rustler::init!("rule_engine_nif");

/// Parse GRL rules and evaluate against a set of facts.
/// Returns {ok, {Decision, Reason}} or {error, Reason} as Gleam Result.
#[rustler::nif(schedule = "DirtyCpu")]
fn evaluate(
    domain: String,
    rules_grl: String,
    fact_tuples: Vec<(String, String)>,
) -> NifResult<(String, String)> {
    // Parse GRL rules
    let rules = match GRLParser::parse_rules(&rules_grl) {
        Ok(r) => r,
        Err(e) => {
            return Ok(("Error".into(), format!("GRL parse error: {}", e)));
        }
    };

    // Build knowledge base
    let kb = KnowledgeBase::new(&domain);
    let mut engine = RustRuleEngine::new(kb);

    for r in &rules {
        if let Err(e) = engine.knowledge_base().add_rule(r.clone()) {
            return Ok(("Error".into(), format!("Rule add error: {}", e)));
        }
    }

    // Set facts from tuples
    let mut facts = Facts::new();
    for (key, value) in &fact_tuples {
        match value.as_str() {
            "true" => facts.set(key, Value::Boolean(true)),
            "false" => facts.set(key, Value::Boolean(false)),
            _ => facts.set(key, Value::String(value.clone())),
        }
    }

    // Set defaults
    let decision_key = format!("{}.Decision", domain);
    let reason_key = format!("{}.Reason", domain);
    facts.set(&decision_key, Value::String("NoAction".into()));
    facts.set(&reason_key, Value::String("Default".into()));

    // Execute
    if let Err(e) = engine.execute(&mut facts) {
        return Ok(("Error".into(), format!("Execution error: {}", e)));
    }

    let decision = match facts.get(&decision_key) {
        Some(Value::String(s)) => s.clone(),
        _ => "NoAction".into(),
    };
    let reason = match facts.get(&reason_key) {
        Some(Value::String(s)) => s.clone(),
        _ => "Unknown".into(),
    };

    Ok((decision, reason))
}

/// Parse GRL rules and return the count (for validation).
#[rustler::nif]
fn parse_rules_count(rules_grl: String) -> NifResult<i64> {
    match GRLParser::parse_rules(&rules_grl) {
        Ok(rules) => Ok(rules.len() as i64),
        Err(_) => Ok(-1),
    }
}

/// Return the engine version string.
#[rustler::nif]
fn engine_version() -> NifResult<String> {
    Ok("rust-rule-engine/1.20.1 RETE-UL".to_string())
}
