(** Reference oracle for the ZigVM file primitive seam
    ([engines/zigvm/src/prim_file.zig]).

    The oracle mirrors the 22-function algebra one to one, including the total
    error mapping, the bounded read, the sorted directory listing and the
    positioned I/O contract. It additionally implements LAW-VFS-08 (the path
    jail) with [openat2(RESOLVE_BENEATH)], which the Zig seam does not yet do;
    a differential run against ZigVM is therefore expected to disagree on that
    law and agree on the others.

    Every operation is total: it returns [Error e] with a typed [error] and
    never raises. The oracle is evidence only and is never linked into a
    runtime path. *)

type error =
  | Enoent  (** no such file or directory *)
  | Eacces  (** permission denied, or a jail violation (path leaves the root) *)
  | Eisdir  (** the path is a directory *)
  | Enotdir  (** a path component is not a directory *)
  | Eexist  (** already exists *)
  | Ebadf  (** closed or invalid handle, or a positioned op the mode forbids *)
  | Name_too_long  (** path too long *)
  | Too_large  (** a read exceeded the fuel bound *)
  | Io  (** any other OS error, mapped totally *)
  | Out_of_memory  (** allocation failure *)

val error_to_string : error -> string

(** Total translation of a Unix error into the seam's error algebra. *)
val error_of_unix : Unix.error -> error

type mode = Read | Write | Read_write | Append

type file_type = Device | Directory | Other | Regular | Symlink

type access = No_access | Access_read | Access_write | Access_read_write

type file_info = {
  size : int64;
  file_type : file_type;
  access : access;
  inode : int64;
  links : int;
  mtime_s : int64;
  atime_s : int64;
  ctime_s : int64;
  mode : int;
  uid : int;
  gid : int;
  major_device : int64;  (** encoded [st_dev] *)
  minor_device : int64;  (** encoded [st_rdev] *)
}

(** An opened directory descriptor: every path in this module resolves
    beneath it. *)
type root

(** An open file handle. *)
type handle

type jail_strategy =
  | Openat2_resolve_beneath  (** kernel-enforced: symlinks cannot escape either *)
  | Normalized_openat
      (** fallback when [openat2] is unavailable: absolute paths and [..]
          components are refused before [openat]; symlink escapes are not
          caught by this strategy *)

val jail_strategy : unit -> jail_strategy

val open_root : string -> (root, error) result
val close_root : root -> unit

val write_file : root -> string -> string -> (unit, error) result

(** [read_file root path max]: the whole file, or [Too_large] when its size
    exceeds [max] bytes (the fuel cap). *)
val read_file : root -> string -> int -> (string, error) result

val delete : root -> string -> (unit, error) result

(** Names directly under the sub-directory, sorted; [.] and [..] excluded. *)
val list_dir : root -> string -> (string list, error) result

val open_ : root -> string -> mode -> (handle, error) result
val read : handle -> bytes -> (int, error) result
val write : handle -> string -> (unit, error) result

(** Positioned read of up to [Bytes.length buf] bytes at absolute offset
    [pos]; returns the count (0 at or after EOF). The shared offset is not
    consumed. *)
val pread : handle -> int64 -> bytes -> (int, error) result

(** Positioned write of all bytes at absolute offset [pos]. *)
val pwrite : handle -> int64 -> string -> (unit, error) result

val handle_size : handle -> (int64, error) result
val truncate_handle : handle -> int64 -> (unit, error) result
val sync_handle : handle -> (unit, error) result
val close : handle -> unit

val rename : root -> string -> string -> (unit, error) result
val make_dir : root -> string -> (unit, error) result

(** Remove an empty directory. *)
val delete_dir : root -> string -> (unit, error) result

(** [lstat] projection: the link itself, never followed. *)
val read_link_info : root -> string -> (file_info, error) result

(** [stat] projection: symlinks followed, but only beneath the root. *)
val read_file_info : root -> string -> (file_info, error) result

(** glibc [gnu_dev_makedev]. *)
val makedev : int64 -> int64 -> int64

val fd_to_int : Unix.file_descr -> int
