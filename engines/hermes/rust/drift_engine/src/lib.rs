// C-ABI wrapper around rust-rule-engine for the Hermes harness.
//
// Protocol (JSON in, JSON out -- the same oracle discipline as gospel/z3/df):
//   input  { "grl":   "<rules in GRL>",
//            "facts": { "<FactName>": { "<Field>": <string|int|float|bool>, ... }, ... } }
//   output { "rules_fired": N, "cycle_count": N,
//            "facts": { ...facts after then-actions ran... } }
//        or { "error": "<reason>" }        -- never a crash across the FFI
//
// The wrapper makes no decisions: it parses, executes, serializes. Every
// judgement about what a fired rule MEANS stays in OCaml.

use rust_rule_engine::engine::engine::RustRuleEngine;
use rust_rule_engine::engine::facts::Facts;
use rust_rule_engine::engine::knowledge_base::KnowledgeBase;
use rust_rule_engine::types::Value;
use std::ffi::{c_char, CStr, CString};

fn eval(input: &str) -> String {
    match eval_inner(input) {
        Ok(out) => out,
        Err(reason) => {
            serde_json::json!({ "error": reason }).to_string()
        }
    }
}

fn eval_inner(input: &str) -> Result<String, String> {
    let parsed: serde_json::Value =
        serde_json::from_str(input).map_err(|e| format!("unreadable input: {e}"))?;
    let grl = parsed
        .get("grl")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "missing grl".to_string())?;
    let fact_objects = parsed
        .get("facts")
        .and_then(|v| v.as_object())
        .ok_or_else(|| "missing facts object".to_string())?;

    let kb = KnowledgeBase::new("hermes-drift");
    kb.add_rules_from_grl(grl)
        .map_err(|e| format!("grl rejected: {e:?}"))?;
    let mut engine = RustRuleEngine::new(kb);

    let facts = Facts::new();
    for (name, fields) in fact_objects {
        // Value has From<serde_json::Value>, so a whole object converts in one
        // step and field access in GRL (Fact.Field) resolves into it.
        facts
            .add_value(name, Value::from(fields.clone()))
            .map_err(|e| format!("fact {name} rejected: {e:?}"))?;
    }

    let result = engine
        .execute(&facts)
        .map_err(|e| format!("execution failed: {e:?}"))?;

    // Facts after then-actions: the observable output the OCaml side compares.
    let mut out_facts = serde_json::Map::new();
    for (name, value) in facts.get_all_facts() {
        let json = serde_json::to_value(&value)
            .map_err(|e| format!("fact {name} unserializable: {e}"))?;
        out_facts.insert(name, json);
    }

    Ok(serde_json::json!({
        "rules_fired": result.rules_fired,
        "cycle_count": result.cycle_count,
        "facts": out_facts,
    })
    .to_string())
}

/// # Safety
/// `input` must be a valid NUL-terminated C string. The returned pointer must be
/// released with `hde_free`. Never panics across the boundary: all failures come
/// back as an {"error": ...} JSON string.
#[no_mangle]
pub unsafe extern "C" fn hde_eval(input: *const c_char) -> *mut c_char {
    let reply = if input.is_null() {
        serde_json::json!({ "error": "null input" }).to_string()
    } else {
        match CStr::from_ptr(input).to_str() {
            Ok(text) => eval(text),
            Err(_) => serde_json::json!({ "error": "input was not utf-8" }).to_string(),
        }
    };
    // A reply containing an interior NUL cannot cross the ABI; degrade loudly.
    CString::new(reply)
        .unwrap_or_else(|_| CString::new("{\"error\":\"interior nul in reply\"}").unwrap())
        .into_raw()
}

/// # Safety
/// `ptr` must have come from `hde_eval` (or be null, which is a no-op).
#[no_mangle]
pub unsafe extern "C" fn hde_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
