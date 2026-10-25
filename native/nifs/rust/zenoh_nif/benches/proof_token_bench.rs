//! Criterion benchmarks for ProofToken tiered enforcement (SC-NIF-012).
//!
//! Validates latency targets:
//! - Tier 0 (Bypass): < 1us
//! - Tier 1 (Session): < 5us (amortized with cache hits)
//! - Tier 2 (Full):    < 10us
//!
//! Run with: `cd native/zenoh_nif && cargo bench --bench proof_token_bench`

use criterion::{black_box, criterion_group, criterion_main, Criterion};

// We can't import from the cdylib crate directly in benchmarks, so we
// duplicate the minimal tier classification logic here for benchmarking.
// The actual enforcement code is tested via NIF integration tests.

/// Tier 0 bypass prefixes
const BYPASS_PREFIXES: &[&str] = &[
    "indrajaal/logs/",
    "indrajaal/metrics/",
    "indrajaal/health/",
];

/// Tier 1 session prefixes
const SESSION_PREFIXES: &[&str] = &[
    "indrajaal/inference/",
    "indrajaal/neural/",
];

/// Tier 2 full enforcement prefixes
const FULL_PREFIXES: &[&str] = &[
    "indrajaal/control/",
    "indrajaal/evolution/",
];

#[derive(Debug, Clone, Copy, PartialEq)]
enum EnforcementTier {
    Bypass,
    Session,
    Full,
}

#[inline]
fn classify_tier(key_expr: &str) -> EnforcementTier {
    for prefix in BYPASS_PREFIXES {
        if key_expr.starts_with(prefix) {
            return EnforcementTier::Bypass;
        }
    }
    for prefix in SESSION_PREFIXES {
        if key_expr.starts_with(prefix) {
            return EnforcementTier::Session;
        }
    }
    for prefix in FULL_PREFIXES {
        if key_expr.starts_with(prefix) {
            return EnforcementTier::Full;
        }
    }
    EnforcementTier::Bypass
}

/// Benchmark Tier 0 classification (bypass — telemetry keys)
fn bench_tier0_classify(c: &mut Criterion) {
    let keys = vec![
        "indrajaal/logs/cluster/node-1",
        "indrajaal/metrics/cpu/usage",
        "indrajaal/health/heartbeat",
        "indrajaal/logs/app/debug/request-123",
    ];

    c.bench_function("tier0_classify_bypass", |b| {
        b.iter(|| {
            for key in &keys {
                let tier = classify_tier(black_box(key));
                assert_eq!(tier, EnforcementTier::Bypass);
            }
        })
    });
}

/// Benchmark Tier 1 classification (session — inference keys)
fn bench_tier1_classify(c: &mut Criterion) {
    let keys = vec![
        "indrajaal/inference/request/uuid-1234",
        "indrajaal/inference/response/uuid-1234",
        "indrajaal/neural/embeddings/batch-42",
        "indrajaal/inference/health",
    ];

    c.bench_function("tier1_classify_session", |b| {
        b.iter(|| {
            for key in &keys {
                let tier = classify_tier(black_box(key));
                assert_eq!(tier, EnforcementTier::Session);
            }
        })
    });
}

/// Benchmark Tier 2 classification (full — control keys)
fn bench_tier2_classify(c: &mut Criterion) {
    let keys = vec![
        "indrajaal/control/guardian/proposal",
        "indrajaal/control/config/update",
        "indrajaal/evolution/genome/mutate",
        "indrajaal/evolution/selection/pressure",
    ];

    c.bench_function("tier2_classify_full", |b| {
        b.iter(|| {
            for key in &keys {
                let tier = classify_tier(black_box(key));
                assert_eq!(tier, EnforcementTier::Full);
            }
        })
    });
}

/// Benchmark HMAC-SHA256 key derivation (one-time cost)
fn bench_hmac_key_derivation(c: &mut Criterion) {
    use sha2::{Sha256, Digest};

    let key_material = b"indrajaal_prometheus_verifier_hmac_key_v21.3.0";

    c.bench_function("hmac_key_derivation_sha256", |b| {
        b.iter(|| {
            let mut hasher = Sha256::new();
            hasher.update(black_box(key_material));
            let _result = hasher.finalize();
        })
    });
}

/// Benchmark full HMAC-SHA256 computation (Tier 2 cost)
fn bench_hmac_sha256_compute(c: &mut Criterion) {
    use hmac::{Hmac, Mac};
    use sha2::Sha256;

    type HmacSha256 = Hmac<Sha256>;

    // Pre-derive key (one-time)
    let key_material = b"indrajaal_prometheus_verifier_hmac_key_v21.3.0";
    let derived_key = {
        use sha2::Digest;
        let mut hasher = Sha256::new();
        hasher.update(key_material);
        hasher.finalize()
    };

    // Typical message: "uuid:canonical_claims:timestamp"
    let message = "550e8400-e29b-41d4-a716-446655440000:action=\"publish\"|key=\"indrajaal/control/config\":2026-03-28T23:00:00.000000Z";

    c.bench_function("hmac_sha256_compute", |b| {
        b.iter(|| {
            let mut mac = HmacSha256::new_from_slice(black_box(&derived_key))
                .expect("HMAC key init");
            mac.update(black_box(message.as_bytes()));
            let _result = mac.finalize();
        })
    });
}

/// Benchmark session cache lookup (Tier 1 hot path)
fn bench_session_cache_lookup(c: &mut Criterion) {
    use std::collections::HashMap;
    use std::time::{Duration, Instant};

    // Simulate a warm cache with 100 entries
    let mut cache = HashMap::new();
    let future = Instant::now() + Duration::from_secs(60);
    for i in 0..100 {
        cache.insert(format!("token_hash_{:04}", i), future);
    }

    c.bench_function("session_cache_hit", |b| {
        b.iter(|| {
            let key = black_box("token_hash_0050");
            if let Some(expires_at) = cache.get(key) {
                let _valid = Instant::now() < *expires_at;
            }
        })
    });
}

criterion_group!(
    benches,
    bench_tier0_classify,
    bench_tier1_classify,
    bench_tier2_classify,
    bench_hmac_key_derivation,
    bench_hmac_sha256_compute,
    bench_session_cache_lookup,
);
criterion_main!(benches);
