import gleeunit/should
import uos_planning_ledger/safety

pub fn accepts_normal_documentation_bytes_test() {
  safety.preflight_text(<<"secret handling is discussed without a value":utf8>>)
  |> should.equal(Ok(Nil))
}

pub fn does_not_treat_risk_hyphenated_prose_as_an_api_token_test() {
  safety.preflight_text(<<"risk-derived-verification-control":utf8>>)
  |> should.equal(Ok(Nil))
}

pub fn rejects_private_keys_before_snapshot_or_hash_test() {
  let bytes = <<
    "-----BEGIN PRIVATE KEY-----\nnot-real-fixture\n-----END PRIVATE KEY-----":utf8,
  >>
  safety.preflight_text(bytes)
  |> should.equal(Error(safety.SensitiveContent("private_key_pem")))
}

pub fn rejects_high_confidence_token_assignments_test() {
  safety.preflight_text(<<"api_key=ABCDEFGHIJKLMNOPQRSTUVWXYZ123456":utf8>>)
  |> should.equal(Error(safety.SensitiveContent("credential_assignment")))
}

pub fn rejects_non_utf8_planning_artifacts_test() {
  safety.preflight_text(<<255, 254, 253>>)
  |> should.equal(Error(safety.NonUtf8Content))
}
