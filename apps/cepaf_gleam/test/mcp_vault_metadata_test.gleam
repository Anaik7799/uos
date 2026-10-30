import cepaf_gleam/mcp/adapters/vault_metadata as vault
import cepaf_gleam/mcp/admission.{type ValidatedCall, ValidatedCall}
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/registry
import cepaf_gleam/mcp/types.{
  ClientProfile, Complete, NonRetryable, Refused, ToolError,
}
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

fn call(tool: String, tenant: String) -> ValidatedCall {
  let assert Ok(spec) = registry.lookup("public", tool)
  ValidatedCall(
    spec,
    principal.from_launcher_env(
      actor: "owner",
      client: ClientProfile("test"),
      workspace_root: "tenant-a",
      session_id: "test",
    ),
    dict.from_list([#("tenant_id", tenant)]),
    None,
    None,
    None,
    None,
  )
}

fn backend(lines: List(String)) -> vault.VaultHandle {
  vault.SupervisedVault(
    "tenant-a",
    False,
    True,
    ["metadata/name"],
    dict.from_list([#("default", "read-only")]),
    lines,
  )
}

pub fn unwired_vault_is_not_reported_sealed_or_healthy_test() {
  list.each(["vault_status", "vault_health"], fn(tool) {
    let assert Refused(ToolError(code, reason, NonRetryable)) =
      vault.execute(vault.UnwiredVault("not connected"), call(tool, "tenant-a"))
    code |> should.equal("VAULT_BACKEND_UNWIRED")
    reason |> should.equal("not connected")
  })
}

pub fn cross_tenant_metadata_refused_test() {
  list.each(
    [
      "vault_status",
      "vault_list_secrets",
      "vault_policy_get",
      "vault_audit_tail",
      "vault_health",
    ],
    fn(tool) {
      let assert Refused(ToolError(code, _, NonRetryable)) =
        vault.execute(backend([]), call(tool, "tenant-b"))
      code |> should.equal("VAULT_CROSS_TENANT_FORBIDDEN")
      let foreign =
        vault.SupervisedVault("tenant-b", False, True, [], dict.new(), [])
      let assert Refused(ToolError(code, _, NonRetryable)) =
        vault.execute(foreign, call(tool, "tenant-a"))
      code |> should.equal("VAULT_CROSS_TENANT_FORBIDDEN")
    },
  )
}

pub fn audit_and_error_redaction_canaries_test() {
  let canaries = [
    "hvs.canary-token",
    "Bearer canary-token",
    "secret_value=canary-password",
    "-----BEGIN PRIVATE KEY-----\ncanary-key\n-----END PRIVATE KEY-----",
  ]
  list.each(canaries, fn(canary) {
    let assert Complete(payload, _) =
      vault.execute(
        backend(["safe audit entry", canary]),
        call("vault_audit_tail", "tenant-a"),
      )
    string.contains(payload, "[REDACTED]") |> should.be_true
    string.contains(payload, "canary") |> should.be_false
    string.contains(payload, "safe audit entry") |> should.be_true
    let assert Refused(ToolError(code, reason, NonRetryable)) =
      vault.execute(
        vault.UnwiredVault(canary),
        call("vault_health", "tenant-a"),
      )
    code |> should.equal("VAULT_BACKEND_UNWIRED")
    reason |> should.equal("[REDACTED]")
  })
}

pub fn supervised_metadata_tools_test() {
  list.each(
    [
      "vault_status",
      "vault_list_secrets",
      "vault_policy_get",
      "vault_audit_tail",
      "vault_health",
    ],
    fn(tool) {
      let assert Complete(_, _) =
        vault.execute(backend([]), call(tool, "tenant-a"))
    },
  )
}
