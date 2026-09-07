(* Unified Operational System (UOS) - Hermes Mirage Hypervisor Capability Probe *)
(* Authority: contracts/rules/mirage-migration-policy.md - SC-MIRAGE-MIGRATE-001 *)

type kvm_status = {
  dev_kvm_present : bool;
  dev_kvm_rw_accessible : bool;
  api_version : int option;
}

type qemu_status = {
  binary_path : string option;
  microvm_supported : bool;
  kvm_accel_supported : bool;
}

type solo5_execution_receipt = {
  tender : string;
  unikernel : string;
  exit_code : int;
  output_snippet : string;
  passed : bool;
}

type solo5_status = {
  solo5_hvt_path : string option;
  solo5_spt_path : string option;
  solo5_virtio_path : string option;
  hvt_execution : solo5_execution_receipt option;
  spt_execution : solo5_execution_receipt option;
  virtio_execution : solo5_execution_receipt option;
}

type hypervisor_probe_result = {
  schema : string;
  timestamp_utc : string;
  host : string;
  kvm : kvm_status;
  qemu : qemu_status;
  solo5 : solo5_status;
  overall_readiness : string;
  execution_policy : string;
  deployment_admission : string;
}

external c_kvm_get_api_version : unit -> int = "caml_kvm_get_api_version"

let query_real_kvm_api_version () : int option =
  try
    let ver = c_kvm_get_api_version () in
    if ver >= 0 then Some ver else None
  with _ -> None

let find_binary name =
  let candidate_dirs =
    match Sys.getenv_opt "PATH" with
    | Some p -> String.split_on_char ':' p
    | None -> ["/usr/bin"; "/usr/local/bin"; "/bin"]
  in
  let rec search = function
    | [] -> None
    | dir :: rest ->
        let full = Filename.concat dir name in
        if Sys.file_exists full && (try (Unix.stat full).Unix.st_perm land 0o111 <> 0 with _ -> false) then
          Some full
        else
          search rest
  in
  search candidate_dirs

let contains_substring s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub = 0 then true
  else if len_s < len_sub then false
  else
    let rec check i j =
      if j = len_sub then true
      else if i + j >= len_s then false
      else if String.get s (i + j) = String.get sub j then check i (j + 1)
      else check (i + 1) 0
    in
    check 0 0

let check_qemu_feature args pattern =
  try
    let null_in = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0o600 in
    let r_pipe, w_pipe = Unix.pipe () in
    let pid = Unix.create_process "qemu-system-x86_64" (Array.append [| "qemu-system-x86_64" |] args) null_in w_pipe w_pipe in
    Unix.close null_in;
    Unix.close w_pipe;
    let ic = Unix.in_channel_of_descr r_pipe in
    let buf = Buffer.create 1024 in
    (try
       while true do
         let line = input_line ic in
         Buffer.add_string buf line;
         Buffer.add_char buf '\n'
       done
     with End_of_file -> ());
    close_in ic;
    ignore (Unix.waitpid [] pid);
    contains_substring (Buffer.contents buf) pattern
  with _ -> false

let probe_kvm () =
  let dev_kvm_present = Sys.file_exists "/dev/kvm" in
  let dev_kvm_rw_accessible =
    if dev_kvm_present then
      try
        let fd = Unix.openfile "/dev/kvm" [Unix.O_RDWR] 0o600 in
        Unix.close fd;
        true
      with _ -> false
    else false
  in
  let api_version =
    if dev_kvm_rw_accessible then query_real_kvm_api_version ()
    else None
  in
  { dev_kvm_present; dev_kvm_rw_accessible; api_version }

let probe_qemu () =
  let binary_path = find_binary "qemu-system-x86_64" in
  let microvm_supported = match binary_path with
    | Some _ -> check_qemu_feature [| "-machine"; "help" |] "microvm"
    | None -> false
  in
  let kvm_accel_supported = match binary_path with
    | Some _ -> check_qemu_feature [| "-accel"; "help" |] "kvm"
    | None -> false
  in
  { binary_path; microvm_supported; kvm_accel_supported }

let allowed_prefixes = [
  "/home/an/dev/ver/zigvm/_opam/bin/";
  "/usr/bin/";
  "/usr/local/bin/";
]

let is_allowed_tender bin =
  if String.length bin = 0 || bin.[0] <> '/' then false
  else if String.starts_with ~prefix:"/tmp" bin || String.starts_with ~prefix:"/var/tmp" bin then false
  else
    let base = Filename.basename bin in
    (base = "solo5-hvt" || base = "solo5-spt" || base = "solo5-virtio-run") &&
    List.exists (fun prefix -> String.starts_with ~prefix bin) allowed_prefixes

let is_valid_elf_file path =
  try
    let ic = open_in_bin path in
    let magic = really_input_string ic 4 in
    close_in ic;
    magic = "\x7fELF"
  with _ -> false

let is_successful_execution ~tender ~exit_code ~output =
  let base = Filename.basename tender in
  if contains_substring output "ABORT" then false
  else
    let has_bindings = contains_substring output "Solo5: Bindings version" in
    let has_exit0 = contains_substring output "Solo5: solo5_exit(0) called" in
    if base = "solo5-virtio-run" then
      exit_code = 83 && has_bindings && has_exit0
    else
      exit_code = 0 && has_bindings && has_exit0

let run_tender_test bin_opt unikernel_rel _expected_codes args_list =
  match bin_opt with
  | None -> None
  | Some bin ->
      if not (is_allowed_tender bin) then None
      else
        let uos_root = "/home/an/NAS-setup/uos" in
        let unikernel_path = Filename.concat uos_root ("var/mirage/unikernels/" ^ unikernel_rel) in
        if not (Sys.file_exists unikernel_path) then None
        else
          let st = try Unix.stat unikernel_path with _ -> { Unix.st_dev = 0; st_ino = 0; st_kind = Unix.S_REG; st_perm = 0; st_nlink = 0; st_uid = 0; st_gid = 0; st_rdev = 0; st_size = 0; st_atime = 0.; st_mtime = 0.; st_ctime = 0. } in
          if st.Unix.st_size < 10000 || not (is_valid_elf_file unikernel_path) then None
          else
            let deadline = Unix.gettimeofday () +. 5.0 in
            try
              let null_in = Unix.openfile "/dev/null" [Unix.O_RDONLY] 0o600 in
              let r_pipe, w_pipe = Unix.pipe () in
              Unix.set_nonblock r_pipe;
              let argv = Array.of_list (bin :: unikernel_path :: args_list) in
              let pid = Unix.fork () in
              if pid = 0 then begin
                Unix.close r_pipe;
                ignore (Unix.setsid ());
                Unix.dup2 null_in Unix.stdin;
                Unix.close null_in;
                Unix.dup2 w_pipe Unix.stdout;
                Unix.dup2 w_pipe Unix.stderr;
                Unix.close w_pipe;
                Unix.execv bin argv
              end;
              Unix.close null_in;
              Unix.close w_pipe;

              let buf = Bytes.create 1024 in
              let output_chunks = ref [] in
              let total_bytes = ref 0 in
              let max_bytes = 65536 in
              let eof = ref false in

              while not !eof do
                let now = Unix.gettimeofday () in
                let remaining = deadline -. now in
                if remaining <= 0.0 then begin
                  eof := true;
                  (try Unix.kill (-pid) Sys.sigkill with _ -> ());
                  (try Unix.kill pid Sys.sigkill with _ -> ());
                end else begin
                  let readable, _, _ = Unix.select [r_pipe] [] [] remaining in
                  if readable = [] then begin
                    eof := true;
                    (try Unix.kill (-pid) Sys.sigkill with _ -> ());
                    (try Unix.kill pid Sys.sigkill with _ -> ());
                  end else begin
                    try
                      let space = max_bytes - !total_bytes in
                      if space <= 0 then eof := true
                      else
                        let to_read = min 1024 space in
                        let n = Unix.read r_pipe buf 0 to_read in
                        if n = 0 then eof := true
                        else begin
                          output_chunks := (Bytes.sub_string buf 0 n) :: !output_chunks;
                          total_bytes := !total_bytes + n;
                          if !total_bytes >= max_bytes then eof := true
                        end
                    with
                    | Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
                    | _ -> eof := true
                  end
                end
              done;
              Unix.close r_pipe;

              let rec wait_loop () =
                let now = Unix.gettimeofday () in
                let remaining = deadline -. now in
                if remaining <= 0.0 then begin
                  (try Unix.kill (-pid) Sys.sigkill with _ -> ());
                  (try Unix.kill pid Sys.sigkill with _ -> ());
                  ignore (Unix.waitpid [] pid);
                  -1
                end else begin
                  match Unix.waitpid [Unix.WNOHANG] pid with
                  | 0, _ ->
                      ignore (Unix.select [] [] [] 0.01);
                      wait_loop ()
                  | _, Unix.WEXITED c -> c
                  | _, Unix.WSIGNALED s -> 128 + s
                  | _, _ -> -1
                end
              in
              let exit_code = wait_loop () in
              let all_output = String.concat "" (List.rev !output_chunks) in
              let passed = is_successful_execution ~tender:bin ~exit_code ~output:all_output in
              let output_snippet =
                if String.length all_output > 200 then String.sub all_output 0 200 else all_output
              in
              Some { tender = bin; unikernel = unikernel_path; exit_code; output_snippet; passed }
            with _ -> None

let probe_solo5 () =
  let solo5_hvt_path = find_binary "solo5-hvt" in
  let solo5_spt_path = find_binary "solo5-spt" in
  let solo5_virtio_path = find_binary "solo5-virtio-run" in
  let hvt_execution = run_tender_test solo5_hvt_path "test_hello.hvt" [0] ["Hello_Solo5"] in
  let spt_execution = run_tender_test solo5_spt_path "test_hello.spt" [0] ["Hello_Solo5"] in
  let virtio_execution = run_tender_test solo5_virtio_path "test_hello.virtio" [0; 83] ["--"; "Hello_Solo5"] in
  {
    solo5_hvt_path;
    solo5_spt_path;
    solo5_virtio_path;
    hvt_execution;
    spt_execution;
    virtio_execution;
  }

let probe_hypervisors () =
  let host = try Unix.gethostname () with _ -> "nas-1" in
  let now = Unix.gmtime (Unix.gettimeofday ()) in
  let timestamp_utc = Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (now.Unix.tm_year + 1900) (now.Unix.tm_mon + 1) now.Unix.tm_mday
    now.Unix.tm_hour now.Unix.tm_min now.Unix.tm_sec in
  let kvm = probe_kvm () in
  let qemu = probe_qemu () in
  let solo5 = probe_solo5 () in
  let (overall_readiness, deployment_admission) =
    match solo5.hvt_execution, solo5.spt_execution, solo5.virtio_execution with
    | Some hvt, Some spt, Some virtio when hvt.passed && spt.passed && virtio.passed ->
        ("solo5_hardware_virtualized_and_spt_verified", "TENDERS_VERIFIED_PHYSICAL_EXECUTION")
    | _ ->
        if kvm.dev_kvm_rw_accessible && qemu.kvm_accel_supported then
          ("hardware_kvm_ready", "NOT_VERIFIED")
        else if qemu.binary_path <> None then
          ("tcg_emulated_only", "NOT_VERIFIED")
        else
          ("hypervisor_unavailable", "NOT_VERIFIED")
  in
  let execution_policy = "two_key_receipt_required_before_admission" in
  {
    schema = "uos-mirage-hypervisor-probe/v1";
    timestamp_utc;
    host;
    kvm;
    qemu;
    solo5;
    overall_readiness;
    execution_policy;
    deployment_admission;
  }

let opt_str = function
  | Some s -> `String s
  | None -> `Null

let opt_int = function
  | Some i -> `Int i
  | None -> `Null

let receipt_to_json = function
  | Some r ->
      `Assoc [
        ("tender", `String r.tender);
        ("unikernel", `String r.unikernel);
        ("exit_code", `Int r.exit_code);
        ("output_snippet", `String r.output_snippet);
        ("passed", `Bool r.passed);
      ]
  | None -> `Null

let probe_to_json p =
  `Assoc [
    ("schema", `String p.schema);
    ("timestamp_utc", `String p.timestamp_utc);
    ("host", `String p.host);
    ("overall_readiness", `String p.overall_readiness);
    ("execution_policy", `String p.execution_policy);
    ("evidence_scope", `String "host_hypervisor_hardware_probe");
    ("deployment_admission", `String p.deployment_admission);
    ("kvm", `Assoc [
      ("dev_kvm_present", `Bool p.kvm.dev_kvm_present);
      ("dev_kvm_rw_accessible", `Bool p.kvm.dev_kvm_rw_accessible);
      ("api_version", opt_int p.kvm.api_version);
    ]);
    ("qemu", `Assoc [
      ("binary_path", opt_str p.qemu.binary_path);
      ("microvm_supported", `Bool p.qemu.microvm_supported);
      ("kvm_accel_supported", `Bool p.qemu.kvm_accel_supported);
    ]);
    ("solo5", `Assoc [
      ("solo5_hvt_path", opt_str p.solo5.solo5_hvt_path);
      ("solo5_spt_path", opt_str p.solo5.solo5_spt_path);
      ("solo5_virtio_path", opt_str p.solo5.solo5_virtio_path);
      ("hvt_execution", receipt_to_json p.solo5.hvt_execution);
      ("spt_execution", receipt_to_json p.solo5.spt_execution);
      ("virtio_execution", receipt_to_json p.solo5.virtio_execution);
    ]);
  ]
