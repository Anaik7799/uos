mod kube_apply;
mod render;
mod spec;

use anyhow::Result;
use clap::{Parser, Subcommand};
use spec::LabSpec;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "nas-k8s-lab")]
#[command(about = "Rust-only configuration for the nas-1 Kubernetes/Rook-Ceph VM lab")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Print the selected lab topology and safety gates.
    Summary,
    /// Render host, VM, kubeadm, and Kubernetes configuration artifacts.
    Render {
        /// Output directory for generated artifacts.
        #[arg(long, default_value = "k8s-lab/rendered")]
        out: PathBuf,
    },
    /// Apply Kubernetes-side configuration using kube-rs.
    Apply,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let spec = LabSpec::default();
    spec.validate_safety_invariants()
        .map_err(|e| anyhow::anyhow!(e))?;

    match cli.command {
        Command::Summary => {
            println!("{}", spec.summary());
            Ok(())
        }
        Command::Render { out } => render::render_all(&spec, &out),
        Command::Apply => kube_apply::apply_all(&spec).await,
    }
}
