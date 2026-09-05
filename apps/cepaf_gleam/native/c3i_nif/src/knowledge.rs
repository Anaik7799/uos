//! Knowledge NIFs — search the Zettelkasten holons table.
//!
//! ZK [zk-3346fc607a1ef9e6] "Stub That Lies" anti-pattern: prior version
//! queried a `knowledge` table that doesn't exist in the planning Smriti.db,
//! so always returned `{"total": 0}`. Real ZK lives in the KMS database
//! (`sub-projects/c3i/data/kms/smriti.db::holons`, ~36k rows).
//!
//! STAMP: SC-IKE-001, SC-NIF-001, SC-AGUI-UI-003, SC-TRUTH-001

use crate::db::{execute_with_backoff, open_kms_db};
use rusqlite::params;
use rustler::NifResult;
use serde::Serialize;

#[derive(Debug, Serialize)]
struct KnowledgeResult {
    query: String,
    results: Vec<KnowledgeEntry>,
    total: usize,
}

#[derive(Debug, Serialize)]
struct KnowledgeEntry {
    id: String,
    title: String,
    content: String,
    source: String,
}

#[rustler::nif(schedule = "DirtyCpu")]
pub fn knowledge_search(query: String) -> NifResult<String> {
    // Trim and reject empty queries early so callers see {total:0} instead of
    // a 36k-row scan.
    let q = query.trim();
    if q.is_empty() {
        let data = KnowledgeResult {
            query: query.clone(),
            results: Vec::new(),
            total: 0,
        };
        return Ok(serde_json::to_string(&data).unwrap_or_else(|_| "{}".into()));
    }

    if let Ok(conn) = open_kms_db() {
        // Probe `holons` table presence.
        let has_holons: bool = execute_with_backoff(|| {
            conn.query_row(
                "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='holons'",
                [],
                |row| row.get::<_, i64>(0),
            )
        })
        .map(|c| c > 0)
        .unwrap_or(false);

        if has_holons {
            // Try FTS5 first (fast), fall back to LIKE if fts5 module missing.
            let fts_results: Result<Vec<KnowledgeEntry>, String> = execute_with_backoff(|| {
                let mut stmt = conn.prepare(
                    "SELECT h.holon_uuid, h.title, h.content, COALESCE(h.cluster, h.level) \
                     FROM holons_fts JOIN holons h ON h.rowid = holons_fts.rowid \
                     WHERE holons_fts MATCH ?1 \
                     ORDER BY rank LIMIT 50",
                )?;
                let rows = stmt.query_map(params![q], |row| {
                    Ok(KnowledgeEntry {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        content: row.get::<_, String>(2)?.chars().take(2000).collect(),
                        source: row.get(3)?,
                    })
                })?;
                let mut entries = Vec::new();
                for r in rows {
                    entries.push(r?);
                }
                Ok(entries)
            });

            let entries = match fts_results {
                Ok(e) => e,
                Err(_) => {
                    // FTS5 module unavailable — LIKE fallback.
                    let pattern = format!("%{}%", q);
                    execute_with_backoff(|| {
                        let mut stmt = conn.prepare(
                            "SELECT holon_uuid, title, content, COALESCE(cluster, level) \
                             FROM holons \
                             WHERE title LIKE ?1 OR content LIKE ?1 \
                             ORDER BY updated_at DESC LIMIT 50",
                        )?;
                        let rows = stmt.query_map(params![pattern], |row| {
                            Ok(KnowledgeEntry {
                                id: row.get(0)?,
                                title: row.get(1)?,
                                content: row.get::<_, String>(2)?.chars().take(2000).collect(),
                                source: row.get(3)?,
                            })
                        })?;
                        let mut entries = Vec::new();
                        for r in rows {
                            entries.push(r?);
                        }
                        Ok(entries)
                    })
                    .unwrap_or_else(|_| Vec::new())
                }
            };

            let total = entries.len();
            let data = KnowledgeResult {
                query,
                results: entries,
                total,
            };
            return Ok(serde_json::to_string(&data).unwrap_or_else(|_| "{}".into()));
        }
    }

    // Final fallback — empty envelope (caller's UI fallback chain handles this).
    let data = KnowledgeResult {
        query,
        results: Vec::new(),
        total: 0,
    };
    Ok(serde_json::to_string(&data).unwrap_or_else(|_| "{}".into()))
}
