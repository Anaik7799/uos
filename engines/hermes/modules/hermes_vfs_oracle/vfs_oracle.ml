(* Reference oracle for engines/zigvm/src/prim_file.zig. See vfs_oracle.mli. *)

open Ctypes
open Foreign

type error =
  | Enoent
  | Eacces
  | Eisdir
  | Enotdir
  | Eexist
  | Ebadf
  | Name_too_long
  | Too_large
  | Io
  | Out_of_memory

let error_to_string = function
  | Enoent -> "enoent"
  | Eacces -> "eacces"
  | Eisdir -> "eisdir"
  | Enotdir -> "enotdir"
  | Eexist -> "eexist"
  | Ebadf -> "ebadf"
  | Name_too_long -> "name_too_long"
  | Too_large -> "too_large"
  | Io -> "io"
  | Out_of_memory -> "out_of_memory"

(* Mirrors prim_file.zig mapErr: a total switch with an Io default. EXDEV and
   ELOOP are what openat2(RESOLVE_BENEATH) returns when a path or a symlink
   would leave the root; the seam's law names that outcome a denial. *)
let error_of_unix (e : Unix.error) : error =
  match e with
  | Unix.ENOENT -> Enoent
  | Unix.EACCES | Unix.EPERM -> Eacces
  | Unix.EISDIR -> Eisdir
  | Unix.ENOTDIR -> Enotdir
  | Unix.EEXIST -> Eexist
  | Unix.EBADF -> Ebadf
  | Unix.ENAMETOOLONG -> Name_too_long
  | Unix.ENOMEM -> Out_of_memory
  | Unix.EXDEV | Unix.ELOOP -> Eacces
  | _ -> Io

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
  major_device : int64;
  minor_device : int64;
}

type root = { dirfd : int; root_path : string }

type handle = { fd : int; mutable is_open : bool }

type jail_strategy = Openat2_resolve_beneath | Normalized_openat

(* On Unix, Unix.file_descr is the int fd. *)
external fd_to_int : Unix.file_descr -> int = "%identity"
external fd_of_int : int -> Unix.file_descr = "%identity"

(* ---- libc bindings (x86_64 Linux constants) -------------------------------- *)

let o_rdonly = 0
let o_wronly = 1
let o_rdwr = 2
let o_creat = 0o100
let o_trunc = 0o1000
let o_nofollow = 0o400000
let o_directory = 0o200000
let o_cloexec = 0o2000000
let o_path = 0o10000000
let at_fdcwd = -100
let at_removedir = 0x200
let resolve_beneath = 0x08
let sys_openat2 = 437
let open_how_size = 24

let openat_c =
  foreign ~check_errno:true "openat"
    (int @-> string @-> int @-> int @-> returning int)

let syscall_c =
  foreign ~check_errno:true "syscall"
    (long @-> int @-> string @-> ptr void @-> size_t @-> returning long)

let renameat_c =
  foreign ~check_errno:true "renameat"
    (int @-> string @-> int @-> string @-> returning int)

let mkdirat_c =
  foreign ~check_errno:true "mkdirat" (int @-> string @-> int @-> returning int)

let unlinkat_c =
  foreign ~check_errno:true "unlinkat" (int @-> string @-> int @-> returning int)

let pread_c =
  foreign ~check_errno:true "pread"
    (int @-> ocaml_bytes @-> size_t @-> PosixTypes.off_t
     @-> returning PosixTypes.ssize_t)

let pwrite_c =
  foreign ~check_errno:true "pwrite"
    (int @-> ocaml_string @-> size_t @-> PosixTypes.off_t
     @-> returning PosixTypes.ssize_t)

let openat2 dirfd path flags mode =
  let how = allocate_n uint64_t ~count:3 in
  how <-@ Unsigned.UInt64.of_int flags;
  how +@ 1 <-@ Unsigned.UInt64.of_int mode;
  how +@ 2 <-@ Unsigned.UInt64.of_int resolve_beneath;
  let r =
    syscall_c (Signed.Long.of_int sys_openat2) dirfd path (to_voidp how)
      (Unsigned.Size_t.of_int open_how_size)
  in
  Signed.Long.to_int r

let strategy = ref None

let jail_strategy () =
  match !strategy with
  | Some s -> s
  | None ->
      let s =
        try
          let fd = openat2 at_fdcwd "." (o_rdonly lor o_directory lor o_cloexec) 0 in
          (try Unix.close (fd_of_int fd) with _ -> ());
          Openat2_resolve_beneath
        with Unix.Unix_error (Unix.ENOSYS, _, _) -> Normalized_openat
      in
      strategy := Some s;
      s

(* ---- helpers ------------------------------------------------------------ *)

let wrap f = try Ok (f ()) with Unix.Unix_error (e, _, _) -> Error (error_of_unix e)

let precheck path =
  if String.length path >= 4096 then Error Name_too_long else Ok ()

let is_escaping path =
  (String.length path > 0 && path.[0] = '/')
  || List.exists (fun c -> c = "..") (String.split_on_char '/' path)

(* Open [path] beneath [root]. Under the openat2 strategy the kernel enforces
   the jail (symlinks included); under the fallback, escaping syntax is refused
   before the plain openat. *)
let open_beneath root path flags mode : (int, error) result =
  match precheck path with
  | Error e -> Error e
  | Ok () -> (
      match jail_strategy () with
      | Openat2_resolve_beneath -> wrap (fun () -> openat2 root.dirfd path flags mode)
      | Normalized_openat ->
          if is_escaping path then Error Eacces
          else wrap (fun () -> openat_c root.dirfd path flags mode))

(* Mutating operations resolve the parent directory beneath the root first and
   then act on the basename, so a symlinked parent cannot carry the effect
   outside the jail. *)
let with_parent root path (f : int -> string -> 'a) : ('a, error) result =
  match precheck path with
  | Error e -> Error e
  | Ok () -> (
      let base = Filename.basename path in
      if base = ".." || base = "." || base = "" || base = "/" then Error Eacces
      else
        let dir = Filename.dirname path in
        let dir_fd_result =
          if dir = "." || dir = "" then Ok None
          else
            match
              open_beneath root dir (o_path lor o_directory lor o_cloexec) 0
            with
            | Ok fd -> Ok (Some fd)
            | Error e -> Error e
        in
        match dir_fd_result with
        | Error e -> Error e
        | Ok parent ->
            let pfd = match parent with Some fd -> fd | None -> root.dirfd in
            let result = wrap (fun () -> f pfd base) in
            (match parent with
            | Some fd -> ( try Unix.close (fd_of_int fd) with _ -> ())
            | None -> ());
            result)

(* ---- roots and handles ---------------------------------------------------- *)

let open_root path =
  wrap (fun () ->
      let fd = Unix.openfile path [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0 in
      let st = Unix.fstat fd in
      if st.Unix.st_kind <> Unix.S_DIR then (
        Unix.close fd;
        raise (Unix.Unix_error (Unix.ENOTDIR, "open_root", path)));
      { dirfd = fd_to_int fd; root_path = path })

let close_root r = try Unix.close (fd_of_int r.dirfd) with _ -> ()

let flags_of_mode = function
  | Read -> (o_rdonly, 0)
  | Write -> (o_wronly lor o_creat lor o_trunc, 0o644)
  (* read+write, keep existing contents: the positioned-IO handle. Append is
     the same handle; the seam appends by a positioned write at the size. *)
  | Read_write | Append -> (o_rdwr lor o_creat, 0o644)

let open_ root path mode =
  let flags, md = flags_of_mode mode in
  match open_beneath root path (flags lor o_cloexec) md with
  | Ok fd -> Ok { fd; is_open = true }
  | Error e -> Error e

let close h =
  if h.is_open then (
    h.is_open <- false;
    try Unix.close (fd_of_int h.fd) with _ -> ())

let guard h f = if not h.is_open then Error Ebadf else wrap f

let read h buf = guard h (fun () -> Unix.read (fd_of_int h.fd) buf 0 (Bytes.length buf))

let write h s =
  guard h (fun () ->
      let fd = fd_of_int h.fd in
      let len = String.length s in
      let rec go off =
        if off < len then
          let n = Unix.write_substring fd s off (len - off) in
          go (off + n)
      in
      go 0)

let ssize_to_int v = PosixTypes.Ssize.to_int v

let pread h pos buf =
  guard h (fun () ->
      let want = Bytes.length buf in
      let rec go off =
        if off >= want then off
        else
          let tmp = Bytes.create (want - off) in
          let n =
            ssize_to_int
              (pread_c h.fd (ocaml_bytes_start tmp)
                 (Unsigned.Size_t.of_int (want - off))
                 (PosixTypes.Off.of_int64 (Int64.add pos (Int64.of_int off))))
          in
          if n <= 0 then off
          else (
            Bytes.blit tmp 0 buf off n;
            go (off + n))
      in
      go 0)

let pwrite h pos s =
  guard h (fun () ->
      let len = String.length s in
      let rec go off =
        if off < len then
          let chunk = String.sub s off (len - off) in
          let n =
            ssize_to_int
              (pwrite_c h.fd (ocaml_string_start chunk)
                 (Unsigned.Size_t.of_int (len - off))
                 (PosixTypes.Off.of_int64 (Int64.add pos (Int64.of_int off))))
          in
          if n <= 0 then raise (Unix.Unix_error (Unix.EIO, "pwrite", ""))
          else go (off + n)
      in
      go 0)

let handle_size h = guard h (fun () -> (Unix.LargeFile.fstat (fd_of_int h.fd)).Unix.LargeFile.st_size)

(* Zig: any ftruncate failure is Ebadf, never a panic. *)
let truncate_handle h len =
  if not h.is_open then Error Ebadf
  else try Ok (Unix.LargeFile.ftruncate (fd_of_int h.fd) len) with _ -> Error Ebadf

let sync_handle h = guard h (fun () -> Unix.fsync (fd_of_int h.fd))

(* ---- whole-file operations ------------------------------------------------- *)

let write_file root path bytes =
  match open_ root path Write with
  | Error e -> Error e
  | Ok h ->
      let r = write h bytes in
      close h;
      r

let read_file root path max =
  match open_ root path Read with
  | Error e -> Error e
  | Ok h ->
      let buf = Buffer.create 4096 in
      let chunk = Bytes.create 4096 in
      let rec go () =
        match read h chunk with
        | Error e -> Error e
        | Ok 0 -> Ok (Buffer.contents buf)
        | Ok n ->
            Buffer.add_subbytes buf chunk 0 n;
            if Buffer.length buf > max then Error Too_large else go ()
      in
      let r = go () in
      close h;
      r

let delete root path = with_parent root path (fun pfd base -> ignore (unlinkat_c pfd base 0))

let make_dir root path =
  with_parent root path (fun pfd base -> ignore (mkdirat_c pfd base 0o755))

let delete_dir root path =
  with_parent root path (fun pfd base -> ignore (unlinkat_c pfd base at_removedir))

let rename root from to_ =
  match
    with_parent root from (fun pf bf ->
        with_parent root to_ (fun pt bt -> ignore (renameat_c pf bf pt bt)))
  with
  | Ok (Ok ()) -> Ok ()
  | Ok (Error e) -> Error e
  | Error e -> Error e

let list_dir root path =
  match open_beneath root path (o_rdonly lor o_directory lor o_cloexec) 0 with
  | Error e -> Error e
  | Ok fd ->
      let r =
        try
          let names = Sys.readdir (Printf.sprintf "/proc/self/fd/%d" fd) in
          let l = Array.to_list names in
          Ok (List.sort compare l)
        with Sys_error _ -> Error Io
      in
      (try Unix.close (fd_of_int fd) with _ -> ());
      r

(* ---- stat projections ------------------------------------------------------ *)

let makedev major minor =
  let open Int64 in
  logor
    (logor (logand minor 0xffL) (shift_left (logand major 0xfffL) 8))
    (logor
       (shift_left (logand minor (lognot 0xffL)) 12)
       (shift_left (logand major (lognot 0xfffL)) 32))

let type_of_kind = function
  | Unix.S_REG -> Regular
  | Unix.S_DIR -> Directory
  | Unix.S_LNK -> Symlink
  | Unix.S_CHR | Unix.S_BLK -> Device
  | Unix.S_FIFO | Unix.S_SOCK -> Other

let type_bits = function
  | Unix.S_REG -> 0o100000
  | Unix.S_DIR -> 0o040000
  | Unix.S_LNK -> 0o120000
  | Unix.S_CHR -> 0o020000
  | Unix.S_BLK -> 0o060000
  | Unix.S_FIFO -> 0o010000
  | Unix.S_SOCK -> 0o140000

let info_of_stat (st : Unix.LargeFile.stats) =
  let mode = type_bits st.Unix.LargeFile.st_kind lor st.Unix.LargeFile.st_perm in
  {
    size = st.Unix.LargeFile.st_size;
    file_type = type_of_kind st.Unix.LargeFile.st_kind;
    (* prim_file.zig: owner-write bit set -> read_write, else read *)
    access = (if mode land 0o200 <> 0 then Access_read_write else Access_read);
    inode = Int64.of_int st.Unix.LargeFile.st_ino;
    links = st.Unix.LargeFile.st_nlink;
    mtime_s = Int64.of_float (Float.floor st.Unix.LargeFile.st_mtime);
    atime_s = Int64.of_float (Float.floor st.Unix.LargeFile.st_atime);
    ctime_s = Int64.of_float (Float.floor st.Unix.LargeFile.st_ctime);
    mode;
    uid = st.Unix.LargeFile.st_uid;
    gid = st.Unix.LargeFile.st_gid;
    major_device = Int64.of_int st.Unix.LargeFile.st_dev;
    minor_device = Int64.of_int st.Unix.LargeFile.st_rdev;
  }

let stat_via_path_fd root path flags =
  match open_beneath root path (o_path lor o_cloexec lor flags) 0 with
  | Error e -> Error e
  | Ok fd ->
      let r = wrap (fun () -> info_of_stat (Unix.LargeFile.fstat (fd_of_int fd))) in
      (try Unix.close (fd_of_int fd) with _ -> ());
      r

(* Zig readLinkInfo: an empty path is NameTooLong (bounded-path precheck). *)
let read_link_info root path =
  if path = "" then Error Name_too_long else stat_via_path_fd root path o_nofollow

let read_file_info root path = stat_via_path_fd root path 0
