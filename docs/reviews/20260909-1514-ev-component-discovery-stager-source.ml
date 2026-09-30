#use "/tmp/ev_transport_sync_stage.ml";;
let ()=
  let probe="/tmp/ev_transport_test_discovery.gleam" in
  let bytes=read probe in
  let staged=package^"/test/ev_transport_test_discovery.gleam" in
  write staged bytes;
  write(target^"/discovery-probe-binding.json")(Yojson.Basic.pretty_to_string(`Assoc[
    "candidate",`String revision;"authority",`String "NONE";
    "probe",bound probe staged bytes;
    "stager_sha256",`String(hash(read "/tmp/ev_transport_discovery_stage.ml"))])^"\n")
