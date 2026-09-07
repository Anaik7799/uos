(** MirageOS Unikernel Signatures for UOS (EV-87)
    MirageOS core module types, functor specifications, and Solo5 target contracts.
    Fulfills SC-MIRAGE-001 and Zero-Muda SIL-6 Unikernel safety. *)

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

val string_of_platform : target_platform -> string
val platform_of_string : string -> target_platform option
val validate_manifest : unikernel_manifest -> (unit, string) result
