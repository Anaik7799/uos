// formal/polybench_sm75/seed_05_zero_copy_frame.rs
// PolyBench-SM75 Language 5 (Rust Borrow Checker & Zero-Copy Lifetimes)
// Resolves simultaneous mutable/immutable borrow conflict E0502 via split_at_mut
// with explicit lifetime annotations and zero heap cloning.

#[derive(Debug, PartialEq)]
pub struct Frame<'a> {
    pub header: &'a [u8],
    pub payload: &'a [u8],
}

pub fn split_packet<'a>(buffer: &'a mut [u8], header_len: usize) -> Option<Frame<'a>> {
    if buffer.len() < header_len {
        return None;
    }
    let (hdr, body) = buffer.split_at_mut(header_len);
    if !hdr.is_empty() {
        hdr[0] |= 0x80;
    }
    Some(Frame {
        header: hdr,
        payload: body,
    })
}

fn main() {
    let mut raw = [0x01u8, 0x02, 0x03, 0x04, 0xAA, 0xBB, 0xCC];
    let frame = split_packet(&mut raw, 4).expect("valid frame");
    assert_eq!(frame.header, &[0x81, 0x02, 0x03, 0x04]);
    assert_eq!(frame.payload, &[0xAA, 0xBB, 0xCC]);
    let hdr0 = frame.header[0];
    let plen = frame.payload.len();
    assert!(split_packet(&mut raw, 16).is_none());
    println!("POLYBENCH_RUST_BORROW_PASS:hdr0=0x{:02X}:payload_len={}", hdr0, plen);
}
