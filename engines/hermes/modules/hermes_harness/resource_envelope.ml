(* Fail-closed resource-envelope preflight.

   This session hit the exact failure this prevents: the shared /tmp tmpfs
   filled to 99% and a test run died with ENOSPC -- a resource used without
   being checked. The evidence chain already refuses to record what it did not
   verify; this extends that discipline to resources. Nothing is consumed that
   was not checked, and an unknown or insufficient resource fails closed with a
   fractal diagnostic, never a raw crash.

   The decision is pure ([evaluate]).  R31 forbids this lower algebra from
   touching the world directly, so operational observation remains explicitly
   unavailable until a controlled owner can supply an opaque receipt-bound
   observation.  [check_one] therefore refuses without probing the host. *)

type executable_identity = { device : int; inode : int }

type kernel_capability =
  | Proc_self_fd_executable
  | Rlimit_as
  | Process_group_signalling

type resource =
  | Temp_space of { bytes_needed : int; margin : float }
  | Disk_space of { path : string; bytes_needed : int; margin : float }
  | Binary of { name : string; env_var : string option }
  | Exact_executable of { path : string; expected : executable_identity }
  | Kernel_capability of kernel_capability
  | Writable of string
  | Frozen_reference of { root : string }

type reported_fact =
  | Space of { available_bytes : int }
  | Presence of bool
  | Executable of {
      identity : executable_identity;
      regular_file : bool;
      executable : bool;
    }
  | Capability of { capability : kernel_capability; supported : bool }
  | Unknown of string

type observation_receipt = unit
type observation = reported_fact * observation_receipt

type operational_status =
  | Implemented_unavailable of string

type check = {
  resource : resource;
  met : bool;
  detail : string;
  receipt_bound : bool;
}

let floor_bytes = 512 * 1024 * 1024
let default_margin = 0.20

let operational_unavailable_reason =
  "controlled external-resource observation owner injection is not implemented"

let operational_status = Implemented_unavailable operational_unavailable_reason

(* --------------------------------------------------------------- decision *)

(* A space requirement is met only when BOTH the proportional margin holds AND
   the absolute floor would still be respected after the estimated consumption.
   The floor is not decoration: a percentage margin alone can be satisfied by a
   large denominator while almost nothing is actually free (the tmpfs failed at
   99%). The floor is the backstop the margin is not. Margin is checked first so
   the reason a caller sees is the tighter of the two constraints. *)
let space_verdict ~needed ~margin available =
  let threshold = float_of_int needed *. (1. +. margin) in
  let margin_ok = float_of_int available >= threshold in
  let floor_ok = available - needed >= floor_bytes in
  if not margin_ok then
    ( false,
      Printf.sprintf
        "insufficient headroom: %d bytes free, need %d with a %.0f%% margin (>= %.0f)"
        available needed (margin *. 100.) threshold )
  else if not floor_ok then
    ( false,
      Printf.sprintf "below the safety floor: only %d bytes would remain after %d, floor is %d"
        (available - needed) needed floor_bytes )
  else
    ( true,
      Printf.sprintf "%d bytes free, %d needed + %.0f%% margin, floor %d satisfied" available
        needed (margin *. 100.) floor_bytes )

let evaluate resource observation =
  let met, detail =
    match (resource, observation) with
    | ( (Temp_space { bytes_needed; margin } | Disk_space { bytes_needed; margin; _ }),
        Space { available_bytes } ) ->
        space_verdict ~needed:bytes_needed ~margin available_bytes
    | (Temp_space _ | Disk_space _), Unknown reason ->
        (false, "could not determine free space: " ^ reason)
    | (Temp_space _ | Disk_space _), Presence _ ->
        (false, "unexpected observation: a presence fact for a space resource")
    | (Temp_space _ | Disk_space _), (Executable _ | Capability _) ->
        (false, "unexpected observation: a supervision fact for a space resource")
    | (Binary _ | Writable _ | Frozen_reference _), Presence present ->
        (present, if present then "present" else "absent")
    | (Binary _ | Writable _ | Frozen_reference _), Unknown reason ->
        (false, "could not determine: " ^ reason)
    | (Binary _ | Writable _ | Frozen_reference _), Space _ ->
        (false, "unexpected observation: a space fact for a presence resource")
    | (Binary _ | Writable _ | Frozen_reference _), (Executable _ | Capability _) ->
        (false, "unexpected observation: a supervision fact for a presence resource")
    | Exact_executable _, Unknown reason ->
        (false, "could not determine exact executable identity: " ^ reason)
    | ( Exact_executable { expected; _ },
        Executable { identity; regular_file; executable } ) ->
        if not regular_file then (false, "the observed executable object is not a regular file")
        else if not executable then (false, "the observed executable object is not executable")
        else if identity.device <> expected.device || identity.inode <> expected.inode then
          ( false,
            Printf.sprintf "executable object mismatch: observed %d:%d, expected %d:%d"
              identity.device identity.inode expected.device expected.inode )
        else
          ( true,
            Printf.sprintf "regular executable object %d:%d matches" identity.device
              identity.inode )
    | Exact_executable _, (Space _ | Presence _ | Capability _) ->
        (false, "unexpected observation: not an executable-identity fact")
    | Kernel_capability _, Unknown reason ->
        (false, "could not determine kernel capability: " ^ reason)
    | ( Kernel_capability required,
        Capability { capability = observed; supported } ) ->
        if required <> observed then
          (false, "unexpected observation: a different kernel capability was observed")
        else
          ( supported,
            if supported then "kernel capability supported"
            else "kernel capability unsupported" )
    | Kernel_capability _, (Space _ | Presence _ | Executable _) ->
        (false, "unexpected observation: not a matching kernel-capability fact")
  in
  { resource; met; detail; receipt_bound = false }

(* -------------------------------------------------- operational boundary *)

(* No raw probe is permitted here.  The opaque [observation] carrier is
   intentionally unconstructable through this interface until its controlled
   owner and receipt injection are reviewed.  Refusing is safer than retaining
   a shadow observer that would split authorization, timeout, redaction, and
   resource identity from R31. *)
let check_one resource =
  let check = evaluate resource (Unknown operational_unavailable_reason) in
  { check with receipt_bound = false }

let preflight resources = List.map check_one resources
let satisfied checks = List.for_all (fun check -> check.met && check.receipt_bound) checks

let unmet_checks checks =
  List.filter (fun check -> not check.met || not check.receipt_bound) checks

(* ------------------------------------------------------------ diagnostics *)

(* Each unmet resource becomes a fractal diagnostic. The invariant, enforced by
   the structure tests: every one Blocks_credit and carries a resource hazard
   whose realises_h1 is false. A resource shortfall proves nothing about the
   candidate, so it can never grant OR deny parity credit -- it only refuses to
   proceed. The origin locates the fault: Environment for the world running
   short, Control for the harness's own store, Evidence for a missing snapshot. *)
let diagnostic_of_check (check : check) : Fractal_diagnostic.t option =
  if check.met then None
  else
    let open Fractal_diagnostic in
    match check.resource with
    | Temp_space _ ->
        Some
          (make ~hazard:"HZ-RES-TEMP" ~level:L4_fixture ~origin:Environment
             ~impact:Blocks_credit ~node:"hermes.resource.temp_space"
             ~subject:"effective-temp-filesystem"
             ~message:("temp filesystem preflight failed: " ^ check.detail)
             ~cause:
               "the effective temp filesystem ($TMPDIR or /tmp) has too little free space \
                for the operation and its margin"
             ~fix:
               "free space on the temp filesystem, or point $TMPDIR at a disk with room; a \
                near-full temp fs is an ENOSPC waiting to happen"
             ())
    | Disk_space { path; _ } ->
        Some
          (make ~hazard:"HZ-RES-DISK" ~level:L4_fixture ~origin:Environment
             ~impact:Blocks_credit ~node:"hermes.resource.disk_space" ~subject:path
             ~message:("disk preflight failed for " ^ path ^ ": " ^ check.detail)
             ~cause:
               "the filesystem holding fixtures, the evidence database and _build has too \
                little free space"
             ~fix:"free space on the project disk before capturing or comparing" ())
    | Binary { name; _ } ->
        Some
          (make ~hazard:"HZ-RES-BIN" ~level:L2_capability ~origin:Environment
             ~impact:Blocks_credit ~node:"hermes.resource.binary" ~subject:name
             ~message:("required tool unavailable: " ^ name ^ " (" ^ check.detail ^ ")")
             ~cause:"an external oracle the operation depends on is not resolvable on PATH"
             ~fix:
               ("install or provision " ^ name
              ^ ", or set its override variable; absence is surfaced up front, not mid-run")
             ())
    | Exact_executable { path; _ } ->
        Some
          (make ~hazard:"HZ-RES-BIN" ~level:L2_capability ~origin:Environment
             ~impact:Blocks_credit ~node:"hermes.resource.executable_identity" ~subject:path
             ~message:("exact executable identity unavailable for " ^ path ^ " (" ^ check.detail ^ ")")
             ~cause:
               "the configured executable path does not resolve to the declared regular executable object"
             ~fix:
               "restore the declared executable object and re-create the consuming configuration; the execute-time adapter must still recheck its digest"
             ())
    | Kernel_capability capability ->
        let subject =
          match capability with
          | Proc_self_fd_executable -> "proc-self-fd-executable"
          | Rlimit_as -> "rlimit-as"
          | Process_group_signalling -> "process-group-signalling"
        in
        Some
          (make ~hazard:"HZ-RES-KERNEL" ~level:L2_capability ~origin:Environment
             ~impact:Blocks_credit ~node:"hermes.resource.kernel_capability" ~subject
             ~message:("kernel supervision preflight failed for " ^ subject ^ " (" ^ check.detail ^ ")")
             ~cause:
               "the host could not confirm a kernel facility required by the supervised worker"
             ~fix:
               "use a platform that exposes the declared facility, or keep the supervised operation unavailable"
             ())
    | Writable path ->
        Some
          (make ~hazard:"HZ-RES-DB" ~level:L6_receipt ~origin:Control ~impact:Blocks_credit
             ~node:"hermes.resource.writable" ~subject:path
             ~message:("evidence path not writable: " ^ path ^ " (" ^ check.detail ^ ")")
             ~cause:
               "the harness cannot write where it records receipts; a read-only store \
                silently loses evidence"
             ~fix:"make the path (or its parent directory) writable before recording evidence"
             ())
    | Frozen_reference { root } ->
        Some
          (make ~hazard:"HZ-RES-REF" ~level:L4_fixture ~origin:Evidence ~impact:Blocks_credit
             ~node:"hermes.resource.frozen_reference" ~subject:root
             ~message:("frozen reference missing or empty: " ^ root ^ " (" ^ check.detail ^ ")")
             ~cause:"the snapshot the candidate is measured against is absent from this checkout"
             ~fix:"restore external/hermes_source at the pinned snapshot" ())

let to_diagnostics checks = List.filter_map diagnostic_of_check checks

(* -------------------------------------------------------------- rendering *)

let describe_resource = function
  | Temp_space { bytes_needed; margin } ->
      Printf.sprintf "temp space >= %d bytes (+%.0f%% margin)" bytes_needed (margin *. 100.)
  | Disk_space { path; bytes_needed; margin } ->
      Printf.sprintf "disk %s >= %d bytes (+%.0f%% margin)" path bytes_needed (margin *. 100.)
  | Binary { name; _ } -> Printf.sprintf "binary %s resolvable" name
  | Exact_executable { path; expected } ->
      Printf.sprintf "executable %s is object %d:%d" path expected.device expected.inode
  | Kernel_capability Proc_self_fd_executable ->
      "kernel supports executable /proc/self/fd objects"
  | Kernel_capability Rlimit_as -> "kernel exposes RLIMIT_AS"
  | Kernel_capability Process_group_signalling ->
      "kernel supports process-group signalling"
  | Writable path -> Printf.sprintf "path %s writable" path
  | Frozen_reference { root } -> Printf.sprintf "frozen reference at %s" root

let render_check check =
  Printf.sprintf "[%s] %s -- %s"
    (if check.met && check.receipt_bound then "OK  "
     else if check.met then "MODEL"
     else "MISS")
    (describe_resource check.resource) check.detail
