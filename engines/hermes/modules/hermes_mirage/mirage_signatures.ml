(** MirageOS Unikernel Signatures Implementation for UOS (EV-87) *)

type error = [
  | `Disconnected
  | `Device_error of string
  | `Read_error of string
  | `Write_error of string
  | `Invalid_argument of string
  | `Unauthorized
]

type write_error = [
  | `Disconnected
  | `Device_error of string
  | `Write_error of string
  | `No_space
  | `Read_only
]

type block_info = {
  read_write : bool;
  sector_size : int;
  size_sectors : int64;
}

module type MIRAGE_CLOCK = sig
  val elapsed_ns : unit -> int64
  val period_ns : unit -> int64 option
  val now_iso8601 : unit -> string
end

module type MIRAGE_BLOCK = sig
  type t
  val get_info : t -> block_info
  val read : t -> int64 -> bytes list -> (unit, error) result
  val write : t -> int64 -> bytes list -> (unit, write_error) result
  val disconnect : t -> unit
end

module type MIRAGE_KV = sig
  type t
  type key = string list

  val get : t -> key -> (string, error) result
  val set : t -> key -> string -> (t, write_error) result
  val remove : t -> key -> (t, write_error) result
  val list : t -> key -> (key list, error) result
  val digest : t -> key -> (string, error) result
end

module type MIRAGE_FLOW = sig
  type flow
  val read : flow -> (string option, error) result
  val write : flow -> string -> (unit, write_error) result
  val close : flow -> unit
end

type target_platform =
  | Target_unix
  | Target_solo5_hvt
  | Target_solo5_spt
  | Target_xen
  | Target_qubes

type unikernel_manifest = {
  name : string;
  version : string;
  platform : target_platform;
  memory_mb : int;
  boot_args : string list;
  block_devices : string list;
  network_interfaces : string list;
  zero_trust : bool;
}

let string_of_platform = function
  | Target_unix -> "unix"
  | Target_solo5_hvt -> "solo5-hvt"
  | Target_solo5_spt -> "solo5-spt"
  | Target_xen -> "xen"
  | Target_qubes -> "qubes"

let platform_of_string = function
  | "unix" -> Some Target_unix
  | "solo5-hvt" | "hvt" -> Some Target_solo5_hvt
  | "solo5-spt" | "spt" -> Some Target_solo5_spt
  | "xen" -> Some Target_xen
  | "qubes" -> Some Target_qubes
  | _ -> None

let validate_manifest m =
  if m.name = "" then Error "unikernel name cannot be empty"
  else if m.memory_mb < 2 then Error "unikernel memory must be at least 2 MB"
  else if m.memory_mb > 1024 then Error "unikernel memory cannot exceed 1024 MB in micro-tier"
  else Ok ()
