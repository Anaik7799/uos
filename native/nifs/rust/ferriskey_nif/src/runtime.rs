//! Process-singleton tokio runtime for the NIF.
//!
//! Pattern: same as `c3i_nif::zenoh_nif::get_runtime` (lines 15-24).
//! Single multi-thread runtime shared across every async NIF call so the
//! cost of runtime construction is amortized and we do not contend with
//! the BEAM scheduler.
//!
//! SC-FERRISKEY-NIF-002 — Single OnceCell<Runtime> across all NIFs.
//! SC-FERRISKEY-NIF-009 — NIF panic must not crash BEAM (rustler maps
//! panics to terms; the runtime itself is never re-entered after panic).

use once_cell::sync::OnceCell;
use tokio::runtime::{Builder, Runtime};

static RT: OnceCell<Runtime> = OnceCell::new();

/// Returns the process-wide tokio runtime. First call constructs it.
pub fn get() -> &'static Runtime {
    RT.get_or_init(|| {
        Builder::new_multi_thread()
            .worker_threads(4)
            .thread_name("ferriskey-nif")
            .enable_all()
            .build()
            .expect("ferriskey_nif: failed to construct tokio runtime")
    })
}
