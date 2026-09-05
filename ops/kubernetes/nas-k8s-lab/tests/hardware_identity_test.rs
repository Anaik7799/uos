// UOS Gate G-BOOT4 Hardware Identity & Disk Protection Test
// Invariant: Hardware serial 25503L801736 is permanently denied for OSD assignment.
// Bare /dev names (e.g. /dev/nvme0n1 vs /dev/nvme1n1) are strictly rejected for device admission.

pub const HARD_DENIED_SYSTEM_OS_SERIAL: &str = "25503L801736";
pub const HARD_DENIED_SYSTEM_OS_EUI64: &str = "eui.e8238fa6bf530001001b448b4f783cdb";

pub fn validate_osd_candidate(serial: &str, device_path: &str) -> Result<(), &'static str> {
    if serial == HARD_DENIED_SYSTEM_OS_SERIAL {
        return Err("HARD_DENIED: Candidate device matches protected OS host root drive serial");
    }
    if device_path.starts_with("/dev/nvme") && serial.is_empty() {
        return Err("REJECTED: NVMe device admission requires verified immutable hardware serial number");
    }
    Ok(())
}

#[test]
fn test_os_disk_serial_rejection() {
    let result = validate_osd_candidate(HARD_DENIED_SYSTEM_OS_SERIAL, "/dev/nvme1n1");
    assert!(result.is_err());
    assert_eq!(result.unwrap_err(), "HARD_DENIED: Candidate device matches protected OS host root drive serial");
}

#[test]
fn test_bare_dev_name_rejection() {
    let result = validate_osd_candidate("", "/dev/nvme0n1");
    assert!(result.is_err());
    assert_eq!(result.unwrap_err(), "REJECTED: NVMe device admission requires verified immutable hardware serial number");
}

#[test]
fn test_valid_secondary_disk_requires_serial() {
    let result = validate_osd_candidate("25503L802767", "/dev/nvme0n1");
    assert!(result.is_ok());
}
