//! The `rusty_vault::pki` module implements public key cryptography features, including
//! manipulating certificates as a CA or encrypting a piece of data by using a public key.

use std::{
    any::Any,
    sync::{atomic::AtomicU64, Arc},
    time::Duration,
};

use derive_more::Deref;

use crate::{
    core::Core,
    errors::RvError,
    logical::{secret::Secret, Backend, LogicalBackend, Request, Response},
    modules::Module,
    new_logical_backend, new_logical_backend_internal, new_secret, new_secret_internal,
};

pub mod field;
pub mod path_config_ca;
pub mod path_config_crl;
pub mod path_fetch;
pub mod path_issue;
pub mod path_keys;
pub mod path_revoke;
pub mod path_roles;
pub mod path_root;
pub mod util;

static PKI_BACKEND_HELP: &str = r#"
The PKI backend dynamically generates X509 server and client certificates.

After mounting this backend, configure the CA using the "pem_bundle" endpoint within
the "config/" path.
"#;
const _DEFAULT_LEASE_TTL: Duration = Duration::from_secs(3600_u64);

pub struct PkiModule {
    pub name: String,
    pub backend: Arc<PkiBackend>,
}

pub struct PkiBackendInner {
    pub core: Arc<Core>,
    pub cert_count: AtomicU64,
    pub revoked_cert_count: AtomicU64,
}

#[derive(Deref)]
pub struct PkiBackend {
    #[deref]
    pub inner: Arc<PkiBackendInner>,
}

impl PkiBackend {
    pub fn new(core: Arc<Core>) -> Self {
        Self {
            inner: Arc::new(PkiBackendInner {
                core,
                cert_count: AtomicU64::new(0),
                revoked_cert_count: AtomicU64::new(0),
            }),
        }
    }

    pub fn new_backend(&self) -> LogicalBackend {
        let pki_backend_ref1 = self.inner.clone();
        let pki_backend_ref2 = self.inner.clone();

        let mut backend = new_logical_backend!({
            root_paths: ["config/*", "revoke/*", "crl/rotate"],
            unauth_paths: ["cert/*", "ca/pem", "ca", "crl", "crl/pem"],
            secrets: [{
                secret_type: "pki",
                revoke_handler: pki_backend_ref1.revoke_secret_creds,
                renew_handler: pki_backend_ref2.renew_secret_creds,
            }],
            help: PKI_BACKEND_HELP,
        });

        backend.paths.push(Arc::new(self.roles_path()));
        backend.paths.push(Arc::new(self.config_ca_path()));
        backend.paths.push(Arc::new(self.root_generate_path()));
        backend.paths.push(Arc::new(self.root_delete_path()));
        backend.paths.push(Arc::new(self.fetch_ca_path()));
        backend.paths.push(Arc::new(self.fetch_crl_path()));
        backend.paths.push(Arc::new(self.fetch_cert_path()));
        backend.paths.push(Arc::new(self.fetch_cert_crl_path()));
        backend.paths.push(Arc::new(self.issue_path()));
        backend.paths.push(Arc::new(self.revoke_path()));
        backend.paths.push(Arc::new(self.crl_rotate_path()));
        backend.paths.push(Arc::new(self.keys_generate_path()));
        backend.paths.push(Arc::new(self.keys_import_path()));
        backend.paths.push(Arc::new(self.keys_sign_path()));
        backend.paths.push(Arc::new(self.keys_verify_path()));
        backend.paths.push(Arc::new(self.keys_encrypt_path()));
        backend.paths.push(Arc::new(self.keys_decrypt_path()));

        backend
    }
}

#[maybe_async::maybe_async]
impl PkiBackendInner {
    pub async fn revoke_secret_creds(
        &self,
        _backend: &dyn Backend,
        _req: &mut Request,
    ) -> Result<Option<Response>, RvError> {
        Ok(None)
    }
    pub async fn renew_secret_creds(
        &self,
        _backend: &dyn Backend,
        _req: &mut Request,
    ) -> Result<Option<Response>, RvError> {
        Ok(None)
    }
}

impl PkiModule {
    pub fn new(core: Arc<Core>) -> Self {
        Self { name: "pki".to_string(), backend: Arc::new(PkiBackend::new(core)) }
    }
}

impl Module for PkiModule {
    fn name(&self) -> String {
        self.name.clone()
    }

    fn as_any_arc(self: Arc<Self>) -> Arc<dyn Any + Send + Sync> {
        self
    }

    fn setup(&self, core: &Core) -> Result<(), RvError> {
        let pki = self.backend.clone();
        let pki_backend_new_func = move |_c: Arc<Core>| -> Result<Arc<dyn Backend>, RvError> {
            let mut pki_backend = pki.new_backend();
            pki_backend.init()?;
            Ok(Arc::new(pki_backend))
        };
        core.add_logical_backend("pki", Arc::new(pki_backend_new_func))
    }

    fn cleanup(&self, core: &Core) -> Result<(), RvError> {
        core.delete_logical_backend("pki")
    }
}

