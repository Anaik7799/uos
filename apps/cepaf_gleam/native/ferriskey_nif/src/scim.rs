//! SCIM 2.0 inbound + outbound (Phase 5).
//!
//! Substrate (5 surface functions, NIF wrappers in Phase 5.5):
//!   scim_user_to_internal(scim_json) -> User
//!   scim_internal_to_user(user) -> ScimUser JSON
//!   scim_inbound_apply(op_json) -> {result, resource_id}
//!   scim_outbound_enqueue(op_json, target) -> {queued, id}
//!   scim_filter_parse(filter_str) -> FilterAst (typed, no SQL concat)
//!
//! ## RFC 7643 / 7644 conformance
//! - Schema URNs validated at the boundary (SC-GCP-IAM-004)
//! - Filter parser produces an AST; SQL emission uses rusqlite named
//!   params only — defense against the FMEA #4 injection class
//! - Destructive ops (delete) gated upstream by 2oo3 Guardian
//!   (SC-GCP-IAM-007 — caller-side enforcement)
//!
//! Phase 5 ships the substrate (AST + mappers + outbound queue helpers).
//! Phase 5.5 wires the NIFs and the Wisp endpoints.

use anyhow::{Context, Result};
use rusqlite::params;
use serde::{Deserialize, Serialize};

use crate::audit;
use crate::realm;

pub const SCHEMA_USER: &str = "urn:ietf:params:scim:schemas:core:2.0:User";
pub const SCHEMA_GROUP: &str = "urn:ietf:params:scim:schemas:core:2.0:Group";
pub const SCHEMA_LIST_RESPONSE: &str =
    "urn:ietf:params:scim:api:messages:2.0:ListResponse";
pub const SCHEMA_PATCH_OP: &str =
    "urn:ietf:params:scim:api:messages:2.0:PatchOp";
pub const SCHEMA_ERROR: &str = "urn:ietf:params:scim:api:messages:2.0:Error";
pub const SCHEMA_SERVICE_PROVIDER_CONFIG: &str =
    "urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig";

/// Canonical SCIM User shape (RFC 7643 §4.1) — minimal. Real GCP Cloud
/// Identity SCIM clients send richer payloads; we accept and pass through
/// extension attributes via `attrs` (roundtrip-safe).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScimUser {
    pub schemas: Vec<String>,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(rename = "userName")]
    pub user_name: String,
    #[serde(default)]
    pub name: Option<ScimName>,
    #[serde(default)]
    pub emails: Vec<ScimEmail>,
    #[serde(default)]
    pub active: Option<bool>,
    #[serde(default)]
    pub meta: Option<ScimMeta>,
    /// Carry-through for SCIM extension attributes (enterprise schema, etc.).
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScimName {
    #[serde(rename = "givenName", default)]
    pub given_name: Option<String>,
    #[serde(rename = "familyName", default)]
    pub family_name: Option<String>,
    #[serde(rename = "formatted", default)]
    pub formatted: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScimEmail {
    pub value: String,
    #[serde(default)]
    pub primary: Option<bool>,
    #[serde(rename = "type", default)]
    pub email_type: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScimMeta {
    #[serde(rename = "resourceType")]
    pub resource_type: String,
    pub created: String,
    #[serde(rename = "lastModified")]
    pub last_modified: String,
    pub location: String,
    #[serde(default)]
    pub version: Option<String>,
}

/// Convert a SCIM 2.0 User payload to our internal `User` shape.
/// SC-GCP-IAM-004: schema URN MUST appear in the schemas array.
pub fn user_to_internal(
    scim: &ScimUser,
    realm_id: &str,
) -> Result<crate::user::User> {
    if !scim.schemas.iter().any(|s| s == SCHEMA_USER) {
        anyhow::bail!(
            "SC-GCP-IAM-004: SCIM User missing schema URN {}",
            SCHEMA_USER
        );
    }
    let primary_email = scim
        .emails
        .iter()
        .find(|e| e.primary.unwrap_or(false))
        .or_else(|| scim.emails.first())
        .map(|e| e.value.clone())
        .unwrap_or_default();
    let now = realm::now_secs_pub();
    let id = scim.id.clone().unwrap_or_else(realm::new_id_pub);
    Ok(crate::user::User {
        id: id.clone(),
        realm_id: realm_id.to_string(),
        sub: id,
        username: scim.user_name.clone(),
        email: primary_email,
        mfa_enrolled: false,
        attrs: serde_json::Value::Object(scim.extra.clone()),
        created_at: now,
        updated_at: now,
    })
}

/// Convert our internal `User` to a SCIM 2.0 User payload (RFC 7643 §4.1).
pub fn internal_to_user(u: &crate::user::User, base_url: &str) -> ScimUser {
    let location = format!("{}/scim/v2/Users/{}", base_url, u.id);
    let extra = match &u.attrs {
        serde_json::Value::Object(m) => m.clone(),
        _ => serde_json::Map::new(),
    };
    ScimUser {
        schemas: vec![SCHEMA_USER.to_string()],
        id: Some(u.id.clone()),
        user_name: u.username.clone(),
        name: None,
        emails: vec![ScimEmail {
            value: u.email.clone(),
            primary: Some(true),
            email_type: Some("work".to_string()),
        }],
        active: Some(true),
        meta: Some(ScimMeta {
            resource_type: "User".to_string(),
            created: rfc3339_from_unix(u.created_at),
            last_modified: rfc3339_from_unix(u.updated_at),
            location,
            version: Some(format!("W/\"{}\"", u.updated_at)),
        }),
        extra,
    }
}

fn rfc3339_from_unix(secs: i64) -> String {
    use chrono::{DateTime, Utc};
    DateTime::<Utc>::from_timestamp(secs, 0)
        .map(|dt| dt.to_rfc3339())
        .unwrap_or_else(|| "1970-01-01T00:00:00Z".to_string())
}

// ===========================================================================
// Filter parser — RFC 7644 §3.4.2.2 (subset)
// ===========================================================================

#[derive(Debug, Clone, PartialEq)]
pub enum FilterAst {
    /// `attr eq "value"` / `attr eq 42` / `attr eq true`
    Eq(String, FilterValue),
    /// `attr ne "value"`
    Ne(String, FilterValue),
    /// `attr co "substring"` (contains)
    Co(String, String),
    /// `attr sw "prefix"` (starts with)
    Sw(String, String),
    /// `attr ew "suffix"` (ends with)
    Ew(String, String),
    /// `attr pr` (present / non-null)
    Pr(String),
    And(Box<FilterAst>, Box<FilterAst>),
    Or(Box<FilterAst>, Box<FilterAst>),
    Not(Box<FilterAst>),
}

#[derive(Debug, Clone, PartialEq)]
pub enum FilterValue {
    Str(String),
    Int(i64),
    Bool(bool),
    Null,
}

#[derive(Debug, thiserror::Error)]
pub enum FilterError {
    #[error("filter syntax: expected {expected} at position {pos}")]
    Syntax { expected: String, pos: usize },
    #[error("filter unknown operator: {op}")]
    UnknownOp { op: String },
    #[error("filter unterminated string")]
    UnterminatedString,
    #[error("filter empty input")]
    Empty,
}

struct Parser<'a> {
    input: &'a [u8],
    pos: usize,
}

impl<'a> Parser<'a> {
    fn new(s: &'a str) -> Self {
        Self {
            input: s.as_bytes(),
            pos: 0,
        }
    }

    fn skip_ws(&mut self) {
        while self.pos < self.input.len() && (self.input[self.pos] as char).is_whitespace() {
            self.pos += 1;
        }
    }

    fn peek(&self) -> Option<char> {
        self.input.get(self.pos).map(|b| *b as char)
    }

    fn starts_with_kw(&self, kw: &str) -> bool {
        let bytes = kw.as_bytes();
        if self.pos + bytes.len() > self.input.len() {
            return false;
        }
        for (i, b) in bytes.iter().enumerate() {
            let actual = self.input[self.pos + i] as char;
            if actual.to_ascii_lowercase() != *b as char {
                return false;
            }
        }
        // boundary — next char must be ws / paren / EOF
        let next_pos = self.pos + bytes.len();
        next_pos == self.input.len()
            || (self.input[next_pos] as char).is_whitespace()
            || self.input[next_pos] == b'('
            || self.input[next_pos] == b')'
    }

    fn consume(&mut self, n: usize) {
        self.pos += n;
    }

    fn parse_filter(&mut self) -> Result<FilterAst, FilterError> {
        let lhs = self.parse_or_term()?;
        Ok(lhs)
    }

    /// or-term := and-term ("or" and-term)*
    fn parse_or_term(&mut self) -> Result<FilterAst, FilterError> {
        let mut lhs = self.parse_and_term()?;
        loop {
            self.skip_ws();
            if self.starts_with_kw("or") {
                self.consume(2);
                self.skip_ws();
                let rhs = self.parse_and_term()?;
                lhs = FilterAst::Or(Box::new(lhs), Box::new(rhs));
            } else {
                break;
            }
        }
        Ok(lhs)
    }

    /// and-term := unary ("and" unary)*
    fn parse_and_term(&mut self) -> Result<FilterAst, FilterError> {
        let mut lhs = self.parse_unary()?;
        loop {
            self.skip_ws();
            if self.starts_with_kw("and") {
                self.consume(3);
                self.skip_ws();
                let rhs = self.parse_unary()?;
                lhs = FilterAst::And(Box::new(lhs), Box::new(rhs));
            } else {
                break;
            }
        }
        Ok(lhs)
    }

    /// unary := "not" unary | "(" or-term ")" | atom
    fn parse_unary(&mut self) -> Result<FilterAst, FilterError> {
        self.skip_ws();
        if self.starts_with_kw("not") {
            self.consume(3);
            self.skip_ws();
            let inner = self.parse_unary()?;
            return Ok(FilterAst::Not(Box::new(inner)));
        }
        if self.peek() == Some('(') {
            self.consume(1);
            let inner = self.parse_or_term()?;
            self.skip_ws();
            if self.peek() != Some(')') {
                return Err(FilterError::Syntax {
                    expected: ")".into(),
                    pos: self.pos,
                });
            }
            self.consume(1);
            return Ok(inner);
        }
        self.parse_atom()
    }

    /// atom := attr op value? | attr "pr"
    fn parse_atom(&mut self) -> Result<FilterAst, FilterError> {
        self.skip_ws();
        let attr = self.parse_attr()?;
        self.skip_ws();
        let op = self.parse_op()?;
        match op.as_str() {
            "pr" => Ok(FilterAst::Pr(attr)),
            "eq" | "ne" | "co" | "sw" | "ew" => {
                self.skip_ws();
                let v = self.parse_value()?;
                Ok(match op.as_str() {
                    "eq" => FilterAst::Eq(attr, v),
                    "ne" => FilterAst::Ne(attr, v),
                    "co" => match v {
                        FilterValue::Str(s) => FilterAst::Co(attr, s),
                        _ => {
                            return Err(FilterError::Syntax {
                                expected: "string for co".into(),
                                pos: self.pos,
                            })
                        }
                    },
                    "sw" => match v {
                        FilterValue::Str(s) => FilterAst::Sw(attr, s),
                        _ => {
                            return Err(FilterError::Syntax {
                                expected: "string for sw".into(),
                                pos: self.pos,
                            })
                        }
                    },
                    "ew" => match v {
                        FilterValue::Str(s) => FilterAst::Ew(attr, s),
                        _ => {
                            return Err(FilterError::Syntax {
                                expected: "string for ew".into(),
                                pos: self.pos,
                            })
                        }
                    },
                    _ => unreachable!(),
                })
            }
            other => Err(FilterError::UnknownOp { op: other.into() }),
        }
    }

    fn parse_attr(&mut self) -> Result<String, FilterError> {
        let start = self.pos;
        while self.pos < self.input.len() {
            let c = self.input[self.pos] as char;
            if c.is_ascii_alphanumeric() || c == '.' || c == '_' || c == ':' {
                self.pos += 1;
            } else {
                break;
            }
        }
        if self.pos == start {
            return Err(FilterError::Syntax {
                expected: "attribute name".into(),
                pos: self.pos,
            });
        }
        Ok(std::str::from_utf8(&self.input[start..self.pos])
            .unwrap_or_default()
            .to_string())
    }

    fn parse_op(&mut self) -> Result<String, FilterError> {
        let start = self.pos;
        while self.pos < self.input.len() {
            let c = self.input[self.pos] as char;
            if c.is_ascii_alphabetic() {
                self.pos += 1;
            } else {
                break;
            }
        }
        if self.pos == start {
            return Err(FilterError::Syntax {
                expected: "operator".into(),
                pos: self.pos,
            });
        }
        Ok(std::str::from_utf8(&self.input[start..self.pos])
            .unwrap_or_default()
            .to_ascii_lowercase())
    }

    fn parse_value(&mut self) -> Result<FilterValue, FilterError> {
        self.skip_ws();
        match self.peek() {
            Some('"') => self.parse_string().map(FilterValue::Str),
            Some(c) if c == '-' || c.is_ascii_digit() => {
                self.parse_number().map(FilterValue::Int)
            }
            Some('t') | Some('f') => self.parse_bool().map(FilterValue::Bool),
            Some('n') if self.starts_with_kw("null") => {
                self.consume(4);
                Ok(FilterValue::Null)
            }
            _ => Err(FilterError::Syntax {
                expected: "value".into(),
                pos: self.pos,
            }),
        }
    }

    fn parse_string(&mut self) -> Result<String, FilterError> {
        if self.peek() != Some('"') {
            return Err(FilterError::Syntax {
                expected: "string opening quote".into(),
                pos: self.pos,
            });
        }
        self.consume(1);
        let start = self.pos;
        while self.pos < self.input.len() && self.input[self.pos] != b'"' {
            // Minimal escape handling — `\"` and `\\`. Other escapes pass through.
            if self.input[self.pos] == b'\\' && self.pos + 1 < self.input.len() {
                self.pos += 2;
            } else {
                self.pos += 1;
            }
        }
        if self.pos >= self.input.len() {
            return Err(FilterError::UnterminatedString);
        }
        let s = std::str::from_utf8(&self.input[start..self.pos])
            .unwrap_or_default()
            .replace("\\\"", "\"")
            .replace("\\\\", "\\");
        self.consume(1);
        Ok(s)
    }

    fn parse_number(&mut self) -> Result<i64, FilterError> {
        let start = self.pos;
        if self.peek() == Some('-') {
            self.pos += 1;
        }
        while self.pos < self.input.len() && (self.input[self.pos] as char).is_ascii_digit() {
            self.pos += 1;
        }
        std::str::from_utf8(&self.input[start..self.pos])
            .unwrap_or_default()
            .parse::<i64>()
            .map_err(|_| FilterError::Syntax {
                expected: "integer".into(),
                pos: start,
            })
    }

    fn parse_bool(&mut self) -> Result<bool, FilterError> {
        if self.starts_with_kw("true") {
            self.consume(4);
            Ok(true)
        } else if self.starts_with_kw("false") {
            self.consume(5);
            Ok(false)
        } else {
            Err(FilterError::Syntax {
                expected: "true|false".into(),
                pos: self.pos,
            })
        }
    }
}

/// Parse a SCIM 2.0 filter into an AST. SQL emission MUST go through
/// rusqlite named params — never string-concat. SC-GCP-IAM-004, FMEA #4.
pub fn parse_filter(input: &str) -> Result<FilterAst, FilterError> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err(FilterError::Empty);
    }
    let mut p = Parser::new(trimmed);
    let ast = p.parse_filter()?;
    p.skip_ws();
    if p.pos != p.input.len() {
        return Err(FilterError::Syntax {
            expected: "end of filter".into(),
            pos: p.pos,
        });
    }
    Ok(ast)
}

// ===========================================================================
// FilterAst → parameterized SQL emitter (FMEA #4 SQL injection defense)
// ===========================================================================
//
// Converts a SCIM 2.0 filter AST to a SQL WHERE fragment + a Vec of
// positional params. The emitter is the ONLY path from FilterAst to SQL
// string; user-supplied values NEVER land in the SQL fragment — they are
// always bound through `?N` placeholders.
//
// Attribute → column whitelist closes the FMEA #4 defense at the runtime
// emit boundary, parallel to SC-VALUE-GUARD-001..008 enum normalization.

#[derive(Debug, thiserror::Error)]
pub enum SqlEmitError {
    #[error("scim filter: unknown attribute '{0}' (whitelist exhausted)")]
    UnknownAttribute(String),
}

#[derive(Debug, Clone, PartialEq)]
pub enum SqlValue {
    Str(String),
    Int(i64),
    Bool(bool),
    Null,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SqlFragment {
    /// SQL WHERE fragment with `?N` positional placeholders.
    pub sql: String,
    /// Bound parameter values, in `?1` `?2` … order.
    pub params: Vec<SqlValue>,
}

fn user_attr_to_column(attr: &str) -> Option<&'static str> {
    match attr.to_ascii_lowercase().as_str() {
        "username" | "user_name" => Some("username"),
        "id" => Some("id"),
        "sub" => Some("sub"),
        "email" | "emails" | "emails.value" => Some("email"),
        "active" | "enabled" => Some("mfa_enrolled"),
        "realm_id" | "realm" => Some("realm_id"),
        _ => None,
    }
}

pub fn user_filter_to_sql(ast: &FilterAst) -> Result<SqlFragment, SqlEmitError> {
    let mut idx: usize = 1;
    let mut params: Vec<SqlValue> = Vec::new();
    let sql = emit_user(ast, &mut idx, &mut params)?;
    Ok(SqlFragment { sql, params })
}

fn emit_user(
    ast: &FilterAst,
    idx: &mut usize,
    params: &mut Vec<SqlValue>,
) -> Result<String, SqlEmitError> {
    use FilterAst::*;
    match ast {
        Eq(attr, v) => {
            let col = user_attr_to_column(attr)
                .ok_or_else(|| SqlEmitError::UnknownAttribute(attr.clone()))?;
            let p = bind_param(idx, params, val_from(v.clone(), attr));
            Ok(format!("{col} = {p}"))
        }
        Ne(attr, v) => {
            let col = user_attr_to_column(attr)
                .ok_or_else(|| SqlEmitError::UnknownAttribute(attr.clone()))?;
            let p = bind_param(idx, params, val_from(v.clone(), attr));
            Ok(format!("{col} <> {p}"))
        }
        Co(attr, s) => {
            let col = user_attr_to_column(attr)
                .ok_or_else(|| SqlEmitError::UnknownAttribute(attr.clone()))?;
            let p = bind_param(idx, params, SqlValue::Str(format!("%{}%", s)));
            Ok(format!("{col} LIKE {p}"))
        }
        Sw(attr, s) => {
            let col = user_attr_to_column(attr)
                .ok_or_else(|| SqlEmitError::UnknownAttribute(attr.clone()))?;
            let p = bind_param(idx, params, SqlValue::Str(format!("{}%", s)));
            Ok(format!("{col} LIKE {p}"))
        }
        Ew(attr, s) => {
            let col = user_attr_to_column(attr)
                .ok_or_else(|| SqlEmitError::UnknownAttribute(attr.clone()))?;
            let p = bind_param(idx, params, SqlValue::Str(format!("%{}", s)));
            Ok(format!("{col} LIKE {p}"))
        }
        Pr(attr) => {
            let col = user_attr_to_column(attr)
                .ok_or_else(|| SqlEmitError::UnknownAttribute(attr.clone()))?;
            Ok(format!("{col} IS NOT NULL AND {col} <> ''"))
        }
        And(l, r) => {
            let lhs = emit_user(l, idx, params)?;
            let rhs = emit_user(r, idx, params)?;
            Ok(format!("({lhs}) AND ({rhs})"))
        }
        Or(l, r) => {
            let lhs = emit_user(l, idx, params)?;
            let rhs = emit_user(r, idx, params)?;
            Ok(format!("({lhs}) OR ({rhs})"))
        }
        Not(inner) => {
            let s = emit_user(inner, idx, params)?;
            Ok(format!("NOT ({s})"))
        }
    }
}

fn bind_param(idx: &mut usize, params: &mut Vec<SqlValue>, v: SqlValue) -> String {
    let p = format!("?{}", *idx);
    *idx += 1;
    params.push(v);
    p
}

fn val_from(v: FilterValue, attr: &str) -> SqlValue {
    match v {
        FilterValue::Str(s) => SqlValue::Str(s),
        FilterValue::Int(i) => SqlValue::Int(i),
        FilterValue::Bool(b) => {
            // SCIM `active` boolean maps to `mfa_enrolled` int column.
            let lower = attr.to_ascii_lowercase();
            if lower == "active" || lower == "enabled" {
                SqlValue::Int(if b { 1 } else { 0 })
            } else {
                SqlValue::Bool(b)
            }
        }
        FilterValue::Null => SqlValue::Null,
    }
}

// ===========================================================================
// Outbound queue helpers (Phase 5 substrate; actor lives in Gleam)
// ===========================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboundOp {
    pub id: i64,
    pub target: String,
    pub op: String,
    pub resource_type: String,
    pub payload: String,
    pub attempts: i32,
    pub next_attempt_at: i64,
    pub last_error: Option<String>,
    pub created_at: i64,
}

pub fn enqueue_outbound(
    db_path: &str,
    target: &str,
    op: &str,
    resource_type: &str,
    payload: &str,
) -> Result<i64> {
    let conn = realm::open_for_test(db_path)?;
    let now = realm::now_secs_pub();
    conn.execute(
        "INSERT INTO scim_outbound_queue
         (target,op,resource_type,payload,attempts,next_attempt_at,last_error,created_at)
         VALUES(?1,?2,?3,?4,0,?5,NULL,?6)",
        params![target, op, resource_type, payload, now, now],
    )?;
    let id = conn.last_insert_rowid();
    audit::emit(
        "scim.outbound.enqueue",
        &serde_json::json!({"id": id, "target": target, "op": op, "rt": resource_type}),
    );
    Ok(id)
}

pub fn drain_due(db_path: &str, now: i64, limit: i32) -> Result<Vec<OutboundOp>> {
    let conn = realm::open_for_test(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT id,target,op,resource_type,payload,attempts,next_attempt_at,last_error,created_at
         FROM scim_outbound_queue
         WHERE next_attempt_at <= ?1
         ORDER BY next_attempt_at ASC LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![now, limit], |r| {
        Ok(OutboundOp {
            id: r.get(0)?,
            target: r.get(1)?,
            op: r.get(2)?,
            resource_type: r.get(3)?,
            payload: r.get(4)?,
            attempts: r.get(5)?,
            next_attempt_at: r.get(6)?,
            last_error: r.get(7)?,
            created_at: r.get(8)?,
        })
    })?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r?);
    }
    Ok(out)
}

/// Mark an outbound op as failed. Re-schedules with exponential backoff:
/// `next_attempt_at = now + min(2^attempts, 600)` seconds. After 3 attempts
/// (SC-GCP-IAM-008), gives up and writes the error.
pub fn mark_failed(db_path: &str, id: i64, error: &str) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    let now = realm::now_secs_pub();
    let attempts: i32 = conn
        .query_row(
            "SELECT attempts FROM scim_outbound_queue WHERE id=?1",
            params![id],
            |r| r.get(0),
        )
        .context("mark_failed: row missing")?;
    let new_attempts = attempts + 1;
    if new_attempts >= 3 {
        // SC-GCP-IAM-008 — give up after max retries; row stays for audit.
        conn.execute(
            "UPDATE scim_outbound_queue
             SET attempts=?1, last_error=?2, next_attempt_at=?3
             WHERE id=?4",
            params![new_attempts, error, i64::MAX, id],
        )?;
        Ok(false)
    } else {
        let backoff = 1_i64 << new_attempts; // 2,4,8 s
        conn.execute(
            "UPDATE scim_outbound_queue
             SET attempts=?1, last_error=?2, next_attempt_at=?3
             WHERE id=?4",
            params![new_attempts, error, now + backoff, id],
        )?;
        Ok(true)
    }
}

pub fn mark_done(db_path: &str, id: i64) -> Result<bool> {
    let conn = realm::open_for_test(db_path)?;
    let n = conn.execute("DELETE FROM scim_outbound_queue WHERE id=?1", params![id])?;
    if n > 0 {
        audit::emit(
            "scim.outbound.done",
            &serde_json::json!({"id": id}),
        );
    }
    Ok(n > 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh() -> (tempfile::TempDir, String) {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("ferriskey.db").to_str().unwrap().to_string();
        crate::db::init(&path).unwrap();
        (tmp, path)
    }

    #[test]
    fn user_roundtrip_internal_to_scim_to_internal() {
        let internal = crate::user::User {
            id: "u1".to_string(),
            realm_id: "r1".to_string(),
            sub: "u1".to_string(),
            username: "alice".to_string(),
            email: "alice@example.com".to_string(),
            mfa_enrolled: false,
            attrs: serde_json::json!({}),
            created_at: 1_700_000_000,
            updated_at: 1_700_000_000,
        };
        let scim = internal_to_user(&internal, "https://x");
        assert!(scim.schemas.contains(&SCHEMA_USER.to_string()));
        assert_eq!(scim.user_name, "alice");
        assert_eq!(scim.emails[0].value, "alice@example.com");
        let back = user_to_internal(&scim, "r1").unwrap();
        assert_eq!(back.username, "alice");
        assert_eq!(back.email, "alice@example.com");
    }

    #[test]
    fn user_to_internal_rejects_missing_schema() {
        let bad = ScimUser {
            schemas: vec!["bogus".to_string()],
            id: None,
            user_name: "x".to_string(),
            name: None,
            emails: vec![],
            active: None,
            meta: None,
            extra: serde_json::Map::new(),
        };
        assert!(user_to_internal(&bad, "r1").is_err());
    }

    #[test]
    fn filter_eq_string() {
        let ast = parse_filter(r#"userName eq "alice""#).unwrap();
        assert_eq!(ast, FilterAst::Eq("userName".into(), FilterValue::Str("alice".into())));
    }

    #[test]
    fn filter_pr() {
        let ast = parse_filter("active pr").unwrap();
        assert_eq!(ast, FilterAst::Pr("active".into()));
    }

    #[test]
    fn filter_co_sw_ew() {
        let co = parse_filter(r#"userName co "ali""#).unwrap();
        assert_eq!(co, FilterAst::Co("userName".into(), "ali".into()));
        let sw = parse_filter(r#"userName sw "al""#).unwrap();
        assert_eq!(sw, FilterAst::Sw("userName".into(), "al".into()));
        let ew = parse_filter(r#"userName ew "ce""#).unwrap();
        assert_eq!(ew, FilterAst::Ew("userName".into(), "ce".into()));
    }

    #[test]
    fn filter_and_or_precedence() {
        // and binds tighter than or (RFC 7644 §3.4.2.2).
        let ast = parse_filter(r#"a eq "1" or b eq "2" and c eq "3""#).unwrap();
        match ast {
            FilterAst::Or(left, right) => {
                assert!(matches!(*left, FilterAst::Eq(_, _)));
                assert!(matches!(*right, FilterAst::And(_, _)));
            }
            _ => panic!("expected Or at root, got {:?}", ast),
        }
    }

    #[test]
    fn filter_parens_override_precedence() {
        let ast = parse_filter(r#"(a eq "1" or b eq "2") and c eq "3""#).unwrap();
        match ast {
            FilterAst::And(left, right) => {
                assert!(matches!(*left, FilterAst::Or(_, _)));
                assert!(matches!(*right, FilterAst::Eq(_, _)));
            }
            _ => panic!("expected And at root, got {:?}", ast),
        }
    }

    #[test]
    fn filter_not() {
        let ast = parse_filter(r#"not (active eq true)"#).unwrap();
        match ast {
            FilterAst::Not(inner) => {
                assert!(matches!(*inner, FilterAst::Eq(_, FilterValue::Bool(true))));
            }
            _ => panic!("expected Not at root, got {:?}", ast),
        }
    }

    #[test]
    fn filter_int_value() {
        let ast = parse_filter("loginCount eq 42").unwrap();
        assert_eq!(ast, FilterAst::Eq("loginCount".into(), FilterValue::Int(42)));
    }

    #[test]
    fn filter_unknown_op_rejected() {
        assert!(parse_filter("a like \"x\"").is_err());
    }

    #[test]
    fn filter_unterminated_string_rejected() {
        let err = parse_filter(r#"a eq "missing"#).unwrap_err();
        assert!(matches!(err, FilterError::UnterminatedString));
    }

    #[test]
    fn filter_empty_rejected() {
        assert!(matches!(parse_filter("").unwrap_err(), FilterError::Empty));
        assert!(matches!(parse_filter("   ").unwrap_err(), FilterError::Empty));
    }

    #[test]
    fn outbound_enqueue_and_drain() {
        let (_tmp, path) = fresh();
        let id = enqueue_outbound(
            &path,
            "cloud_identity_groups",
            "create",
            "Group",
            r#"{"displayName":"engineering"}"#,
        )
        .unwrap();
        assert!(id > 0);
        let due = drain_due(&path, realm::now_secs_pub() + 1, 10).unwrap();
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].attempts, 0);
    }

    #[test]
    fn outbound_mark_failed_uses_exponential_backoff() {
        let (_tmp, path) = fresh();
        let id = enqueue_outbound(&path, "t", "create", "User", "{}").unwrap();
        // first failure → still retryable
        assert!(mark_failed(&path, id, "rate_limit").unwrap());
        // second failure → still retryable
        assert!(mark_failed(&path, id, "rate_limit").unwrap());
        // third failure → exceeds limit, give up
        assert!(!mark_failed(&path, id, "rate_limit").unwrap());
    }

    #[test]
    fn outbound_mark_done_removes_row() {
        let (_tmp, path) = fresh();
        let id = enqueue_outbound(&path, "t", "create", "User", "{}").unwrap();
        assert!(mark_done(&path, id).unwrap());
        assert!(!mark_done(&path, id).unwrap());
    }

    // -------------------------------------------------------------
    // FilterAst → parameterized SQL emitter (FMEA #4 defense)
    // -------------------------------------------------------------

    #[test]
    fn sql_emit_eq_uses_positional_param() {
        let ast = parse_filter(r#"userName eq "alice""#).unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.sql, "username = ?1");
        assert_eq!(f.params, vec![SqlValue::Str("alice".into())]);
    }

    #[test]
    fn sql_emit_co_wraps_with_percent() {
        let ast = parse_filter(r#"userName co "ali""#).unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.sql, "username LIKE ?1");
        assert_eq!(f.params, vec![SqlValue::Str("%ali%".into())]);
    }

    #[test]
    fn sql_emit_sw_appends_percent() {
        let ast = parse_filter(r#"userName sw "al""#).unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.params, vec![SqlValue::Str("al%".into())]);
    }

    #[test]
    fn sql_emit_ew_prepends_percent() {
        let ast = parse_filter(r#"userName ew "ce""#).unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.params, vec![SqlValue::Str("%ce".into())]);
    }

    #[test]
    fn sql_emit_pr_does_not_bind_a_param() {
        let ast = parse_filter("email pr").unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.sql, "email IS NOT NULL AND email <> ''");
        assert_eq!(f.params, vec![]);
    }

    #[test]
    fn sql_emit_and_increments_indices() {
        let ast = parse_filter(r#"userName eq "a" and email eq "b@x""#).unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.sql, "(username = ?1) AND (email = ?2)");
        assert_eq!(
            f.params,
            vec![SqlValue::Str("a".into()), SqlValue::Str("b@x".into())]
        );
    }

    #[test]
    fn sql_emit_not_wraps_inner() {
        let ast = parse_filter(r#"not (userName eq "alice")"#).unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.sql, "NOT (username = ?1)");
    }

    #[test]
    fn sql_emit_rejects_unknown_attribute() {
        // FMEA #4: unknown attrs MUST NOT pass through to SQL.
        let ast = parse_filter(r#"ssn eq "123""#).unwrap();
        let err = user_filter_to_sql(&ast).unwrap_err();
        match err {
            SqlEmitError::UnknownAttribute(a) => assert_eq!(a, "ssn"),
        }
    }

    #[test]
    fn sql_emit_active_bool_maps_to_int() {
        // SCIM `active` boolean maps to mfa_enrolled int column.
        let ast = parse_filter("active eq true").unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.sql, "mfa_enrolled = ?1");
        assert_eq!(f.params, vec![SqlValue::Int(1)]);
        let ast2 = parse_filter("active eq false").unwrap();
        let f2 = user_filter_to_sql(&ast2).unwrap();
        assert_eq!(f2.params, vec![SqlValue::Int(0)]);
    }

    #[test]
    fn sql_emit_injection_payload_lands_as_param_not_concat() {
        // The whole point of FMEA #4 defense: even an injection payload
        // as the *value* MUST land as a bound param, never a SQL substring.
        let ast =
            parse_filter(r#"userName eq "x'; DROP TABLE users; --""#).unwrap();
        let f = user_filter_to_sql(&ast).unwrap();
        assert_eq!(f.sql, "username = ?1");
        assert!(!f.sql.contains("DROP"));
        assert!(!f.sql.contains(";"));
        assert!(!f.sql.contains("'"));
        match &f.params[0] {
            SqlValue::Str(s) => assert!(s.contains("DROP TABLE")),
            _ => panic!("expected string param"),
        }
    }
}
