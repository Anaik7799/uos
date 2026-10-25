#[allow(dead_code)]
mod spec {
    include!(env!("UOS_STORAGE_SPEC_SOURCE"));
}
use spec::LabSpec;
use std::process::ExitCode;

enum ProbeError {
    MissingFixture,
}

fn check_policy<F>(expect_valid: bool, mutate: F) -> Result<bool, ProbeError>
where
    F: FnOnce(&mut LabSpec) -> Result<(), ProbeError>,
{
    let mut spec = LabSpec::default();
    mutate(&mut spec)?;
    let valid = spec.validate_safety_invariants().is_ok();
    Ok(if expect_valid { valid } else { !valid })
}

fn run_probe() -> Result<String, ProbeError> {
    if std::env::args_os().nth(1).is_some() {
        return Err(ProbeError::MissingFixture);
    }
    let default_configuration_valid = check_policy(true, |_| Ok(()))?;
    let protected_path_denied = check_policy(false, |s| {
        let os_disk = s.host.os_disk;
        let osd = s.vms.get_mut(0).and_then(|v| v.osd_devices.get_mut(0)).ok_or(ProbeError::MissingFixture)?;
        osd.host_device = os_disk;
        Ok(())
    })?;
    let protected_partition_denied = check_policy(false, |s| {
        let osd = s.vms.get_mut(0).and_then(|v| v.osd_devices.get_mut(0)).ok_or(ProbeError::MissingFixture)?;
        osd.host_device = "/dev/nvme0n1p2";
        Ok(())
    })?;
    let protected_serial_denied = check_policy(false, |s| {
        let osd = s.vms.get_mut(0).and_then(|v| v.osd_devices.get_mut(0)).ok_or(ProbeError::MissingFixture)?;
        osd.host_device = "/dev/nvme9n1";
        osd.serial = Some(LabSpec::HARD_DENIED_SYSTEM_OS_SERIAL);
        Ok(())
    })?;
    let missing_nvme_serial_denied = check_policy(false, |s| {
        let osd = s.vms.get_mut(0).and_then(|v| v.osd_devices.get_mut(0)).ok_or(ProbeError::MissingFixture)?;
        osd.host_device = "/dev/nvme9n1";
        osd.serial = None;
        Ok(())
    })?;
    let renamed_root_path_denied = check_policy(false, |s| {
        s.host.os_disk = "/dev/sdz";
        let osd = s.vms.get_mut(0).and_then(|v| v.osd_devices.get_mut(0)).ok_or(ProbeError::MissingFixture)?;
        osd.host_device = "/dev/sdz";
        Ok(())
    })?;
    let ordinary_candidate_valid = check_policy(true, |s| {
        let osd = s.vms.get_mut(0).and_then(|v| v.osd_devices.get_mut(0)).ok_or(ProbeError::MissingFixture)?;
        osd.host_device = "/dev/nvme9n1";
        osd.serial = Some("fixture_nonprotected_serial");
        Ok(())
    })?;
    let protected_id_configured = LabSpec::HARD_DENIED_SYSTEM_OS_SERIAL == "25503L801736";
    Ok(format!(
        "{{\"schema\":\"uos.storage.policy.v1\",\"status\":\"observed\",\"protected_id_configured\":{},\"checks\":{{\"default_configuration_valid\":{},\"protected_path_denied\":{},\"protected_partition_denied\":{},\"protected_serial_denied\":{},\"missing_nvme_serial_denied\":{},\"renamed_root_path_denied\":{},\"ordinary_candidate_valid\":{}}},\"authority\":\"observation_only\",\"runtime_admission\":\"NOT_GRANTED\"}}",
        protected_id_configured,
        default_configuration_valid,
        protected_path_denied,
        protected_partition_denied,
        protected_serial_denied,
        missing_nvme_serial_denied,
        renamed_root_path_denied,
        ordinary_candidate_valid
    ))
}

fn main() -> ExitCode {
    match run_probe() {
        Ok(line) => {
            println!("{}", line);
            ExitCode::SUCCESS
        }
        Err(ProbeError::MissingFixture) => {
            println!("{{\"status\":\"unavailable\",\"reason\":\"policy_fixture_unavailable\"}}");
            ExitCode::from(1)
        }
    }
}
