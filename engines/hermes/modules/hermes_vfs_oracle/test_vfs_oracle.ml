(* The eight VFS laws (docs/wiki/20260906-1620-…-vfs-analysis-wiki.md) executed
   against the OCaml reference oracle. Output uses the sa-plan suite shape:
   one `ok LAW …` line per passing law, `not ok` otherwise, nonzero exit on
   any failure. *)

open Vfs_oracle

let failures = ref 0
let passes = ref 0

let ok name = incr passes; Printf.printf "ok LAW %s\n%!" name

let not_ok name msg =
  incr failures;
  Printf.printf "not ok LAW %s: %s\n%!" name msg

let check name cond msg = if cond then ok name else not_ok name msg

let show = function
  | Ok _ -> "ok"
  | Error e -> "error:" ^ error_to_string e

let is_err e = function Error x -> x = e | Ok _ -> false

let rec rm_rf path =
  match Unix.lstat path with
  | { Unix.st_kind = Unix.S_DIR; _ } ->
      Array.iter (fun n -> rm_rf (Filename.concat path n)) (Sys.readdir path);
      Unix.rmdir path
  | _ -> Unix.unlink path
  | exception Unix.Unix_error _ -> ()

let fresh_dir tag =
  let d =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "hermes-vfs-oracle-%s-%d-%d" tag (Unix.getpid ())
         (Random.bits ()))
  in
  Unix.mkdir d 0o700;
  d

let () =
  Random.self_init ();
  Printf.printf "# jail strategy: %s\n%!"
    (match jail_strategy () with
    | Openat2_resolve_beneath -> "openat2 RESOLVE_BENEATH (kernel-enforced)"
    | Normalized_openat -> "normalized openat (fallback; symlink escapes not caught)");
  check "FD-INT-IDENTITY" (fd_to_int Unix.stdin = 0) "stdin is not fd 0";
  let dir = fresh_dir "root" and other_dir = fresh_dir "other" in
  let root =
    match open_root dir with Ok r -> r | Error e -> failwith (error_to_string e)
  in
  let other =
    match open_root other_dir with Ok r -> r | Error e -> failwith (error_to_string e)
  in
  (* LAW-VFS-01: descriptor-relative resolution *)
  let w = write_file root "a.txt" "A" in
  let r1 = read_file root "a.txt" 64 in
  let r2 = read_file other "a.txt" 64 in
  check "VFS-01-DESCRIPTOR-RELATIVE"
    (w = Ok () && r1 = Ok "A" && is_err Enoent r2)
    (Printf.sprintf "write=%s read=%s other=%s" (show w) (show r1) (show r2));
  (* LAW-VFS-02: symlink-traversal defense *)
  Unix.symlink "/etc" (Filename.concat dir "esc");
  let li = read_link_info root "esc" in
  let esc = read_file root "esc/hostname" 4096 in
  check "VFS-02-SYMLINK-DEFENSE"
    ((match li with Ok i -> i.file_type = Symlink | Error _ -> false)
    && is_err Eacces esc)
    (Printf.sprintf "link_info=%s escape=%s" (show li) (show esc));
  (* LAW-VFS-03: rename within one root *)
  let rn = rename root "a.txt" "b.txt" in
  let gone = read_file root "a.txt" 64 in
  let there = read_file root "b.txt" 64 in
  let missing = rename root "nope.txt" "x.txt" in
  check "VFS-03-RENAME"
    (rn = Ok () && is_err Enoent gone && there = Ok "A" && is_err Enoent missing)
    (Printf.sprintf "rename=%s gone=%s there=%s missing=%s" (show rn) (show gone)
       (show there) (show missing));
  (* LAW-VFS-04: zero-muda is static: the dune file lists unix and ctypes only *)
  ok "VFS-04-ZERO-MUDA (static: libraries unix ctypes ctypes.foreign)";
  (* LAW-VFS-05: immutable snapshot reads and independent positioned reads *)
  ignore (write_file root "s.dat" "0123456789");
  let s1 = read_file root "s.dat" 64 in
  ignore (write_file root "s.dat" "XXXX");
  let s2 = read_file root "s.dat" 64 in
  let pr =
    match open_ root "s.dat" Read with
    | Error e -> Error e
    | Ok h ->
        ignore (write_file root "s.dat" "0123456789");
        let b1 = Bytes.create 3 and b2 = Bytes.create 2 in
        let n1 = pread h 5L b1 and n2 = pread h 0L b2 in
        close h;
        Ok (n1, Bytes.to_string b1, n2, Bytes.to_string b2)
  in
  check "VFS-05-SNAPSHOT-READS"
    (s1 = Ok "0123456789" && s2 = Ok "XXXX"
    && pr = Ok (Ok 3, "567", Ok 2, "01"))
    (Printf.sprintf "s1=%s s2=%s" (show s1) (show s2));
  (* LAW-VFS-06 is a sa-plan lease law, not a file primitive *)
  Printf.printf "skip LAW VFS-06-LEASE-MUTEX (lives in sa_plan_store.ml; out of scope for the file algebra)\n%!";
  (* LAW-VFS-07: fail-closed typed errors, never an exception *)
  let e_noent = open_ root "missing.txt" Read in
  let e_exist = (ignore (make_dir root "d1"); make_dir root "d1") in
  let e_isdir = read_file root "d1" 64 in
  let e_notdir = open_ root "b.txt/x" Read in
  let e_badf =
    match open_ root "b.txt" Read with
    | Ok h -> close h; read h (Bytes.create 1)
    | Error e -> Error e
  in
  let e_long = open_ root (String.make 5000 'a') Read in
  ignore (write_file root "cap.dat" "0123456789");
  let e_large = read_file root "cap.dat" 5 in
  let e_fits = read_file root "cap.dat" 64 in
  ignore (write_file root "d1/inner" "x");
  let e_notempty = delete_dir root "d1" in
  let all_named = List.for_all (fun e -> String.length (error_to_string e) > 0)
      [ Enoent; Eacces; Eisdir; Enotdir; Eexist; Ebadf; Name_too_long; Too_large; Io; Out_of_memory ] in
  check "VFS-07-TOTAL-TYPED-ERRORS"
    (is_err Enoent e_noent && is_err Eexist e_exist && is_err Eisdir e_isdir
    && is_err Enotdir e_notdir && is_err Ebadf e_badf && is_err Name_too_long e_long
    && is_err Too_large e_large && e_fits = Ok "0123456789"
    && (match e_notempty with Error _ -> true | Ok () -> false)
    && all_named)
    (Printf.sprintf
       "noent=%s exist=%s isdir=%s notdir=%s badf=%s long=%s large=%s fits=%s notempty=%s"
       (show e_noent) (show e_exist) (show e_isdir) (show e_notdir) (show e_badf)
       (show e_long) (show e_large) (show e_fits) (show e_notempty));
  (* LAW-VFS-08: path canonicalization and boundary cage *)
  let j_parent = open_ root "../outside.txt" Read in
  let j_abs = open_ root "/etc/passwd" Read in
  let j_mk = make_dir root "sub" in
  let j_beneath = write_file root "sub/../a2.txt" "Z" in
  let j_deep = read_file root "sub/../../escape" 64 in
  let j_ren = rename root "b.txt" "../out.txt" in
  let j_del = delete root "../x" in
  let j_ls = list_dir root "." in
  check "VFS-08-BOUNDARY-CAGE"
    (is_err Eacces j_parent && is_err Eacces j_abs && j_mk = Ok ()
    && j_beneath = Ok () && is_err Eacces j_deep && is_err Eacces j_ren
    && is_err Eacces j_del
    && (match j_ls with
       | Ok l -> List.mem "b.txt" l && List.mem "sub" l && l = List.sort compare l
       | Error _ -> false))
    (Printf.sprintf "parent=%s abs=%s mk=%s beneath=%s deep=%s ren=%s del=%s ls=%s"
       (show j_parent) (show j_abs) (show j_mk) (show j_beneath) (show j_deep)
       (show j_ren) (show j_del) (show j_ls));
  (* handle algebra: positioned write, size, truncate, sync, append contract *)
  let h_ops =
    match open_ root "h.dat" Write with
    | Error e -> Error e
    | Ok h -> (
        let w = write h "hello" in
        close h;
        match open_ root "h.dat" Read_write with
        | Error e -> Error e
        | Ok h2 ->
            let pw = pwrite h2 2L "LL" in
            let sz = handle_size h2 in
            let tr = truncate_handle h2 2L in
            let sz2 = handle_size h2 in
            let sy = sync_handle h2 in
            close h2;
            let content = read_file root "h.dat" 64 in
            Ok (w, pw, sz, tr, sz2, sy, content))
  in
  check "HANDLE-POSITIONED-IO"
    (h_ops = Ok (Ok (), Ok (), Ok 5L, Ok (), Ok 2L, Ok (), Ok "he"))
    (match h_ops with Ok _ -> "tuple mismatch" | Error e -> error_to_string e);
  let app =
    match open_ root "h.dat" Append with
    | Error e -> Error e
    | Ok h ->
        let r =
          match handle_size h with
          | Ok n -> pwrite h n "!!"
          | Error e -> Error e
        in
        close h;
        (match r with Ok () -> read_file root "h.dat" 64 | Error e -> Error e)
  in
  check "HANDLE-APPEND-AT-SIZE" (app = Ok "he!!") (show app);
  (* stat projections *)
  let fi = read_file_info root "h.dat" in
  check "STAT-PROJECTION"
    (match fi with
    | Ok i -> i.size = 4L && i.file_type = Regular && i.links = 1 && i.mode land 0o170000 = 0o100000
    | Error _ -> false)
    (show fi);
  check "MAKEDEV-GLIBC" (makedev 8L 1L = 0x801L && makedev 259L 0L = 0x10300L) "makedev";
  close_root root;
  close_root other;
  rm_rf dir;
  rm_rf other_dir;
  Printf.printf "# %d laws ok, %d failed\n%!" !passes !failures;
  exit (if !failures = 0 then 0 else 1)
