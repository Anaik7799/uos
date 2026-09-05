(* Minimal ORT binding. See the .mli. *)

open Ctypes
open Foreign

let api_version = 28

let so_candidates =
  [ "venv/lib/python3.13/site-packages/onnxruntime/capi/libonnxruntime.so.1.28.0";
    "libonnxruntime.so.1"; "libonnxruntime.so" ]

let handle =
  lazy
    (let rec first = function
       | [] -> None
       | p :: rest -> (
           match Dl.dlopen ~filename:p ~flags:[ Dl.RTLD_NOW ] with
           | h -> Some h
           | exception _ -> first rest)
     in
     first so_candidates)

(* OrtApiBase holds two function pointers: GetApi, taking a uint32
   version and returning the OrtApi vtable, then GetVersionString. Same
   array-of-cells treatment as the vtable itself. (The C declaration is
   paraphrased rather than quoted: it contains a star-paren sequence
   that would close this comment.) *)
let api_base =
  lazy
    (match Lazy.force handle with
     | None -> None
     | Some from -> (
         match foreign ~from "OrtGetApiBase" (void @-> returning (ptr (ptr void))) with
         | f -> ( match f () with p when is_null p -> None | p -> Some p)
         | exception _ -> None))

let available () = Lazy.force api_base <> None

(* cell [i] of a struct of function pointers *)
let cell base i = !@(base +@ i)

let version_string () =
  match Lazy.force api_base with
  | None -> None
  | Some base -> (
      (* field 1 of OrtApiBase, read WITHOUT the vtable — proves dlopen
         and the entry point independently of any ordinal *)
      match coerce (ptr void) (Foreign.funptr (void @-> returning string)) (cell base 1) with
      | f -> ( match f () with s -> Some s | exception _ -> None)
      | exception _ -> None)

let version_agrees () =
  match version_string () with
  | None -> false
  | Some v ->
      (* the header says 1.28.x; the runtime reports e.g. "1.28.0" *)
      String.length v >= 4 && String.sub v 0 4 = "1.28"

let vtable =
  lazy
    (match Lazy.force api_base with
     | None -> None
     | Some base -> (
         match
           coerce (ptr void) (Foreign.funptr (uint32_t @-> returning (ptr (ptr void))))
             (cell base 0)
         with
         | get_api -> (
             match get_api (Unsigned.UInt32.of_int api_version) with
             | p when is_null p -> None
             | p -> Some p)
         | exception _ -> None))

(* ordinal is 1-based in the extracted table; cell index is 0-based *)
let entry ordinal = match Lazy.force vtable with None -> None | Some v -> Some (cell v (ordinal - 1))

let probe_create_env () =
  if not (available ()) then Error "libonnxruntime could not be loaded"
  else if not (version_agrees ()) then
    (* the ordinal table was extracted from the 1.28 header; against a
       different runtime it may describe nothing *)
    Error
      (Printf.sprintf "runtime version %s does not match the header the ordinals came from"
         (match version_string () with Some v -> v | None -> "(unknown)"))
  else
    (* ordinal 4, NOT 1: the struct begins with CreateStatus,
       GetErrorCode and GetErrorMessage, which use a different macro and
       were missed by the first extraction. Every ordinal was off by
       three. Caught in the isolation probe. *)
    match entry 4 with
    | None -> Error "the OrtApi vtable could not be obtained"
    | Some fp -> (
        match
          coerce (ptr void)
            (Foreign.funptr (int @-> string @-> ptr (ptr void) @-> returning (ptr void)))
            fp
        with
        | create_env -> (
            let out = allocate (ptr void) null in
            (* ORT_LOGGING_LEVEL_ERROR = 3 *)
            match create_env 3 "hermes_vision" out with
            | status when is_null status ->
                if is_null !@out then Error "CreateEnv returned OK but produced no environment"
                else Ok ()
            (* the env is leaked deliberately: this runs in a probe
               process that exits immediately, and ReleaseEnv is another
               ordinal to get wrong for no gain here *)
            | _ -> Error "CreateEnv returned a non-null OrtStatus"
            | exception e -> Error ("CreateEnv raised: " ^ Printexc.to_string e))
        | exception e -> Error ("could not coerce the vtable entry: " ^ Printexc.to_string e))
