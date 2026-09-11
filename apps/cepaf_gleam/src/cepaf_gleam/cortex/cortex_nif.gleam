//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX TYPED RUST NIF INTERFACE
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/cortex/cortex_nif</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <topology>Typed Foreign Function Interface to Cortex Rust Kernel</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-COG-MAX-001, SC-WIRE-001, CHK-07-DRIVE</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

@external(erlang, "cortex_nif", "cortex_ping")
pub fn ping() -> String

@external(erlang, "cortex_nif", "cortex_scrub_pii")
pub fn scrub_pii(input: String) -> String

@external(erlang, "cortex_nif", "cortex_transcribe_audio_pcm16")
pub fn transcribe_audio_pcm16(
  pcm_bytes: BitArray,
  sample_rate: Int,
) -> Result(String, String)

@external(erlang, "cortex_nif", "cortex_infer_local")
pub fn infer_local(
  prompt: String,
  max_tokens: Int,
) -> Result(String, String)

@external(erlang, "cortex_nif", "cortex_check_storage_safety")
pub fn check_storage_safety(serial_query: String) -> Bool
