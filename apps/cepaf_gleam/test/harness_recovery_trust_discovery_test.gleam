import cepaf_gleam/harness/recovery_trust_discovery as discovery
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/resources
import cepaf_gleam/mcp/types
import gleam/string
import gleeunit/should

pub fn unconfigured_production_observation_is_unknown_test() {
  let raw = discovery.observe() |> discovery.to_json
  string.contains(raw, "\"status\":\"UNKNOWN\"") |> should.be_true
  string.contains(raw, "\"reason\":\"PROVIDER_UNCONFIGURED\"") |> should.be_true
  string.contains(raw, "\"authority\":\"NONE\"") |> should.be_true
  string.contains(raw, "\"trusted_roster\":false") |> should.be_true
}

pub fn metadata_resource_is_principal_private_test() {
  let p =
    principal.from_launcher_env(
      actor: "fixture-observer",
      client: types.ClientProfile("codex"),
      workspace_root: "/private/fixture",
      session_id: "ordinary",
    )
  let entry = discovery.resource(discovery.observe(), p)
  entry.visibility |> should.equal(resources.PrivatePrincipalResource)
  entry.owner_actor |> should.equal("fixture-observer")
  entry.workspace_root |> should.equal("/private/fixture")
  let registry = resources.registry([entry], [])
  let assert Ok(#(readback, _)) =
    resources.read_resource(
      registry,
      resources.empty_cache(),
      p,
      discovery.resource_uri,
    )
  readback.content |> should.equal(entry.content)
}
