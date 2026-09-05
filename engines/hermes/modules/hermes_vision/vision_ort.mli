(* The minimal ONNX Runtime binding.

   Reached the way ORT intends: [OrtGetApiBase()] returns a small struct
   whose first field is [GetApi(version)], and that returns the OrtApi
   vtable — 400 function pointers.

   THE VTABLE IS INDEXED, NOT TRANSCRIBED. Every field is a function
   pointer and therefore the same width, so the struct is treated as an
   array of pointer-sized cells and only the entries actually called are
   coerced to real signatures. That avoids reproducing 400 signatures
   correctly, which is the version-fragile part.

   NOTHING HERE IS CALLED UNTIL Vision_ort_safety.preflight PASSES, and
   its final gate runs this in a CHILD process. A wrong ordinal calls
   the wrong function pointer, and the only safe place to discover that
   is somewhere whose death is an exit code rather than ours. *)

val api_version : int          (* ORT_API_VERSION the vendored header states *)

(* Loaded lazily; [None] when the shared object is absent or the
   entry point cannot be found. Never raises. *)
val available : unit -> bool

(* ORT's own version string, from OrtApiBase — read WITHOUT touching the
   vtable, so it proves dlopen and the entry point independently of any
   ordinal being right. *)
val version_string : unit -> string option

(* Does the runtime's reported version agree with the header the
   ordinals were extracted from? A disagreement means the ordinal table
   may not describe this library, which is the drift the safety gates
   exist for. *)
val version_agrees : unit -> bool

(* Create and immediately release an environment, via vtable ordinal 1.
   This is the smallest call that PROVES the offset arithmetic: it
   crosses OrtGetApiBase, GetApi and one indexed function pointer. If
   the ordinal were wrong this is where it would fault.

   [Ok ()] on success, [Error] with the reason otherwise. *)
val probe_create_env : unit -> (unit, string) result
