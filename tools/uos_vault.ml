(* ==============================================================================
   [C3I-SIL6-MSTS] UOS durable vault file store — OCaml side (v1)
   ==============================================================================
   Byte-compatible with apps/cepaf_gleam/src/uos_vault_file.erl:
     "UOSV1" | salt:16 | iv:16 | mac:32 | ciphertext
     keys = PBKDF2-HMAC-SHA256(passphrase, salt, 200000, 64) = aes:32 || mac:32
     ciphertext = AES-256-CBC(aes, iv, pkcs7(secret)); mac = HMAC-SHA256(mac, iv||ct)
   Usage (always from stdin, never an argument, so no token reaches a process
   listing or a shell history):
     uos_vault put  STORE NAME PASSFILE   < secret
     uos_vault get  STORE NAME PASSFILE   > secret   (stdout only)
     uos_vault has  STORE NAME
   The OCaml Telegram client reads its token vault-first through `get_secret`.
   ============================================================================== *)

let magic = "UOSV1"
let iterations = 200000

let hmac_sha256 key data =
  let h = Cryptokit.MAC.hmac_sha256 key in
  h#add_string data;
  h#result

(* PBKDF2-HMAC-SHA256, RFC 8018 §5.2, 64-byte output = two blocks. *)
let pbkdf2 pass salt iters dklen =
  let hlen = 32 in
  let blocks = (dklen + hlen - 1) / hlen in
  let out = Buffer.create (blocks * hlen) in
  for i = 1 to blocks do
    let int_be = Bytes.create 4 in
    Bytes.set int_be 0 (Char.chr ((i lsr 24) land 0xff));
    Bytes.set int_be 1 (Char.chr ((i lsr 16) land 0xff));
    Bytes.set int_be 2 (Char.chr ((i lsr 8) land 0xff));
    Bytes.set int_be 3 (Char.chr (i land 0xff));
    let u = ref (hmac_sha256 pass (salt ^ Bytes.to_string int_be)) in
    let t = Bytes.of_string !u in
    for _ = 2 to iters do
      u := hmac_sha256 pass !u;
      String.iteri (fun j c -> Bytes.set t j (Char.chr (Char.code (Bytes.get t j) lxor Char.code c))) !u
    done;
    Buffer.add_bytes out t
  done;
  String.sub (Buffer.contents out) 0 dklen

let keys pass salt =
  let km = pbkdf2 pass salt iterations 64 in
  (String.sub km 0 32, String.sub km 32 32)

let secret_path store name =
  let safe = String.concat "__" (String.split_on_char '/' name) in
  Filename.concat store (safe ^ ".v1")

let read_passphrase pass_file =
  let ic = open_in_bin pass_file in
  let raw = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let trimmed = String.trim raw in
  if String.length trimmed < 12 then failwith "passphrase_too_short" else trimmed

let random_bytes n =
  let rng = Cryptokit.Random.secure_rng in
  let b = Bytes.create n in
  rng#random_bytes b 0 n;
  Bytes.to_string b

(* Cryptokit's _8000 padding is ISO/IEC 7816-4, not PKCS#7; to stay
   byte-compatible with the Erlang reader we pad PKCS#7 ourselves and run the
   cipher unpadded. *)
let pkcs7 s =
  let n = 16 - (String.length s mod 16) in
  s ^ String.make n (Char.chr n)

let unpkcs7 s =
  let len = String.length s in
  if len = 0 then failwith "decrypt" else
  let n = Char.code s.[len - 1] in
  if n < 1 || n > 16 || n > len then failwith "decrypt" else
  String.sub s 0 (len - n)

let encrypt_pkcs7 pass secret =
  let salt = random_bytes 16 and iv = random_bytes 16 in
  let aes_key, mac_key = keys pass salt in
  let cipher = Cryptokit.Cipher.aes ~mode:Cryptokit.Cipher.CBC ~iv aes_key Cryptokit.Cipher.Encrypt in
  let ct = Cryptokit.transform_string cipher (pkcs7 secret) in
  let mac = hmac_sha256 mac_key (iv ^ ct) in
  magic ^ salt ^ iv ^ mac ^ ct

let constant_time_equal a b =
  String.length a = String.length b
  && (let d = ref 0 in String.iteri (fun i c -> d := !d lor (Char.code c lxor Char.code b.[i])) a; !d = 0)

let decrypt pass blob =
  if String.length blob < 5 + 16 + 16 + 32 || String.sub blob 0 5 <> magic then Error "format" else
  let salt = String.sub blob 5 16 and iv = String.sub blob 21 16 and mac = String.sub blob 37 32 in
  let ct = String.sub blob 69 (String.length blob - 69) in
  let aes_key, mac_key = keys pass salt in
  if not (constant_time_equal mac (hmac_sha256 mac_key (iv ^ ct))) then Error "mac" else
  let cipher = Cryptokit.Cipher.aes ~mode:Cryptokit.Cipher.CBC ~iv aes_key Cryptokit.Cipher.Decrypt in
  (try Ok (unpkcs7 (Cryptokit.transform_string cipher ct)) with _ -> Error "decrypt")

let write_0600 path data =
  let tmp = path ^ ".tmp" in
  let oc = open_out_gen [Open_wronly; Open_creat; Open_trunc; Open_binary] 0o600 tmp in
  output_string oc data; close_out oc;
  Unix.chmod tmp 0o600;
  Sys.rename tmp path

(* Library entry used by telegram_client.ml: None when absent or unreadable. *)
let get_secret store name pass_file =
  let path = secret_path store name in
  if not (Sys.file_exists path) then None else
  try
    let pass = read_passphrase pass_file in
    let ic = open_in_bin path in
    let blob = really_input_string ic (in_channel_length ic) in
    close_in ic;
    match decrypt pass blob with Ok s -> Some s | Error _ -> None
  with _ -> None

let () =
  if !Sys.interactive then () else
  match Array.to_list Sys.argv with
  | _ :: "put" :: store :: name :: pass_file :: _ ->
      let pass = read_passphrase pass_file in
      let secret = String.trim (In_channel.input_all stdin) in
      if secret = "" then (prerr_endline "empty_secret"; exit 2);
      (try Unix.mkdir store 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      write_0600 (secret_path store name) (encrypt_pkcs7 pass secret);
      Printf.printf "stored name=%s bytes=%d store=%s\n" name (String.length secret) store
  | _ :: "get" :: store :: name :: pass_file :: _ ->
      (match get_secret store name pass_file with
       | Some s -> print_string s
       | None -> prerr_endline "not_found_or_mac"; exit 3)
  | _ :: "has" :: store :: name :: _ ->
      if Sys.file_exists (secret_path store name) then print_endline "present" else (print_endline "absent"; exit 1)
  | _ -> prerr_endline "usage: uos_vault put|get STORE NAME PASSFILE | has STORE NAME"; exit 64
