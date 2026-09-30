#use "/tmp/ev_composed_peer_stage.ml";;
let ()=
  require(mode="transport")"transport composition mode required";
  let source="apps/cepaf_gleam/test/ev98_sync_status_runner.gleam" in
  let bytes=candidate source in
  let staged=package^"/test/ev98_sync_status_runner.gleam" in
  write staged bytes;
  let probe="/tmp/ev_sync_reorder_probe.gleam" in
  let probe_bytes=read probe in
  require(probe_bytes=read "/tmp/ev-sync-root-reorder-red-1429/package/test/ev_sync_reorder_probe.gleam")"unchanged independent reorder probe required";
  let probe_staged=package^"/test/ev_sync_reorder_probe.gleam" in
  write probe_staged probe_bytes;
  write(target^"/composition-bindings.json")(Yojson.Basic.pretty_to_string(`Assoc[
    "candidate",`String revision;"authority",`String "NONE";
    "base_bindings_sha256",`String(hash(read(target^"/bindings.json")));
    "additional_candidate",bound("candidate:"^source)staged bytes;
    "additional_probe",bound probe probe_staged probe_bytes;
    "stager_sha256",`String(hash(read "/tmp/ev_transport_sync_stage.ml"))])^"\n");
  print_endline "Added immutable synchronization runner and unchanged independent reorder probes."
