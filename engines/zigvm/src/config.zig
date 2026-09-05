//! config — the VM's experimental-feature flags, and nothing else. Semantic
//! domain: a record of named booleans; comptime `const` flags gate code at
//! compile time, `var` flags at runtime. Data only — no laws beyond the
//! convention that a flag defaulting to `false` claims no capability.
pub const experimental_otlp = true;
pub var experimental_event_wal: bool = false;
