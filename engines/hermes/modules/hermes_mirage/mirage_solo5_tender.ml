(** Solo5 Tender Sandboxing & Unikernel Manifest Generation (EV-87) *)

type tender_config = {
  manifest : Mirage_signatures.unikernel_manifest;
  memory_limit_mb : int;
  seccomp_enabled : bool;
  read_only_root : bool;
  network_tap : string option;
}

let default_tender_config name =
  {
    manifest = {
      name;
      version = "0.1.0-uos";
      platform = Mirage_signatures.Target_solo5_hvt;
      memory_mb = 16;
      boot_args = ["--zero-muda"; "--fail-closed"];
      block_devices = ["storage0"];
      network_interfaces = ["net0"];
      zero_trust = true;
    };
    memory_limit_mb = 16;
    seccomp_enabled = true;
    read_only_root = true;
    network_tap = None;
  }

let generate_manifest_json config =
  let json_props = [
    ("name", `String config.manifest.name);
    ("version", `String config.manifest.version);
    ("platform", `String (Mirage_signatures.string_of_platform config.manifest.platform));
    ("memory_mb", `Int config.memory_limit_mb);
    ("seccomp_enabled", `Bool config.seccomp_enabled);
    ("read_only_root", `Bool config.read_only_root);
    ("zero_trust", `Bool config.manifest.zero_trust);
    ("boot_args", `List (List.map (fun s -> `String s) config.manifest.boot_args));
    ("block_devices", `List (List.map (fun s -> `String s) config.manifest.block_devices));
    ("network_interfaces", `List (List.map (fun s -> `String s) config.manifest.network_interfaces));
  ] in
  Yojson.Basic.pretty_to_string (`Assoc json_props)

let verify_sandbox_safety config =
  if config.memory_limit_mb > 64 then
    Error "micro-unikernel exceeds 64 MB ceiling"
  else if not config.seccomp_enabled then
    Error "seccomp must be enabled for Solo5 sandbox"
  else if not config.read_only_root then
    Error "read_only_root required to enforce zero-muda immutability"
  else
    Ok ()

let cold_start_estimate_ms config =
  (* Solo5 tender cold start is typically 8ms - 15ms *)
  let base_ms = 8.5 in
  let mem_overhead = float_of_int config.memory_limit_mb *. 0.15 in
  base_ms +. mem_overhead
