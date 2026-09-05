let k =
  Array.map Int32.of_string
    [| "0x428a2f98"; "0x71374491"; "0xb5c0fbcf"; "0xe9b5dba5";
       "0x3956c25b"; "0x59f111f1"; "0x923f82a4"; "0xab1c5ed5";
       "0xd807aa98"; "0x12835b01"; "0x243185be"; "0x550c7dc3";
       "0x72be5d74"; "0x80deb1fe"; "0x9bdc06a7"; "0xc19bf174";
       "0xe49b69c1"; "0xefbe4786"; "0x0fc19dc6"; "0x240ca1cc";
       "0x2de92c6f"; "0x4a7484aa"; "0x5cb0a9dc"; "0x76f988da";
       "0x983e5152"; "0xa831c66d"; "0xb00327c8"; "0xbf597fc7";
       "0xc6e00bf3"; "0xd5a79147"; "0x06ca6351"; "0x14292967";
       "0x27b70a85"; "0x2e1b2138"; "0x4d2c6dfc"; "0x53380d13";
       "0x650a7354"; "0x766a0abb"; "0x81c2c92e"; "0x92722c85";
       "0xa2bfe8a1"; "0xa81a664b"; "0xc24b8b70"; "0xc76c51a3";
       "0xd192e819"; "0xd6990624"; "0xf40e3585"; "0x106aa070";
       "0x19a4c116"; "0x1e376c08"; "0x2748774c"; "0x34b0bcb5";
       "0x391c0cb3"; "0x4ed8aa4a"; "0x5b9cca4f"; "0x682e6ff3";
       "0x748f82ee"; "0x78a5636f"; "0x84c87814"; "0x8cc70208";
       "0x90befffa"; "0xa4506ceb"; "0xbef9a3f7"; "0xc67178f2" |]

type context = {
  h : int32 array;
  mutable total_bytes : int64;
  mutable pending : bytes;
  mutable pending_len : int;
}

let initial () =
  { h = Array.map Int32.of_string
          [| "0x6a09e667"; "0xbb67ae85"; "0x3c6ef372"; "0xa54ff53a";
             "0x510e527f"; "0x9b05688c"; "0x1f83d9ab"; "0x5be0cd19" |];
    total_bytes = 0L; pending = Bytes.create 64; pending_len = 0 }

let ( +! ) = Int32.add
let rotr value count =
  Int32.logor (Int32.shift_right_logical value count)
    (Int32.shift_left value (32 - count))
let ch x y z = Int32.logxor (Int32.logand x y) (Int32.logand (Int32.lognot x) z)
let maj x y z =
  Int32.logxor (Int32.logxor (Int32.logand x y) (Int32.logand x z))
    (Int32.logand y z)
let sigma0 x = Int32.logxor (Int32.logxor (rotr x 2) (rotr x 13)) (rotr x 22)
let sigma1 x = Int32.logxor (Int32.logxor (rotr x 6) (rotr x 11)) (rotr x 25)
let small0 x = Int32.logxor (Int32.logxor (rotr x 7) (rotr x 18))
    (Int32.shift_right_logical x 3)
let small1 x = Int32.logxor (Int32.logxor (rotr x 17) (rotr x 19))
    (Int32.shift_right_logical x 10)
let byte bytes index = Char.code (Bytes.get bytes index)

let word_be bytes offset =
  Int32.logor (Int32.shift_left (Int32.of_int (byte bytes offset)) 24)
    (Int32.logor
       (Int32.shift_left (Int32.of_int (byte bytes (offset + 1))) 16)
       (Int32.logor
          (Int32.shift_left (Int32.of_int (byte bytes (offset + 2))) 8)
          (Int32.of_int (byte bytes (offset + 3)))))

let process_block context bytes offset =
  let w = Array.make 64 0l in
  for index = 0 to 15 do w.(index) <- word_be bytes (offset + (index * 4)) done;
  for index = 16 to 63 do
    w.(index) <- small1 w.(index - 2) +! w.(index - 7) +!
      small0 w.(index - 15) +! w.(index - 16)
  done;
  let a = ref context.h.(0) and b = ref context.h.(1) in
  let c = ref context.h.(2) and d = ref context.h.(3) in
  let e = ref context.h.(4) and f = ref context.h.(5) in
  let g = ref context.h.(6) and h = ref context.h.(7) in
  for index = 0 to 63 do
    let t1 = !h +! sigma1 !e +! ch !e !f !g +! k.(index) +! w.(index) in
    let t2 = sigma0 !a +! maj !a !b !c in
    h := !g; g := !f; f := !e; e := !d +! t1;
    d := !c; c := !b; b := !a; a := t1 +! t2
  done;
  let values = [| !a; !b; !c; !d; !e; !f; !g; !h |] in
  for index = 0 to 7 do context.h.(index) <- context.h.(index) +! values.(index) done

let update context source offset length =
  if offset < 0 || length < 0 || offset + length > String.length source then
    invalid_arg "Journal_bundle_digest.update";
  context.total_bytes <- Int64.add context.total_bytes (Int64.of_int length);
  let position = ref offset and remaining = ref length in
  if context.pending_len > 0 then begin
    let take = min !remaining (64 - context.pending_len) in
    Bytes.blit_string source !position context.pending context.pending_len take;
    context.pending_len <- context.pending_len + take;
    position := !position + take; remaining := !remaining - take;
    if context.pending_len = 64 then begin
      process_block context context.pending 0;
      context.pending_len <- 0
    end
  end;
  while !remaining >= 64 do
    let block = Bytes.create 64 in
    Bytes.blit_string source !position block 0 64;
    process_block context block 0;
    position := !position + 64; remaining := !remaining - 64
  done;
  if !remaining > 0 then begin
    Bytes.blit_string source !position context.pending 0 !remaining;
    context.pending_len <- !remaining
  end

let finish context =
  let bit_length = Int64.mul context.total_bytes 8L in
  let final_length = if context.pending_len < 56 then 64 else 128 in
  let final = Bytes.make final_length '\000' in
  Bytes.blit context.pending 0 final 0 context.pending_len;
  Bytes.set final context.pending_len '\x80';
  for index = 0 to 7 do
    let shift = (7 - index) * 8 in
    let octet = Int64.(to_int (logand (shift_right_logical bit_length shift) 0xffL)) in
    Bytes.set final (final_length - 8 + index) (Char.chr octet)
  done;
  for block = 0 to (final_length / 64) - 1 do
    process_block context final (block * 64)
  done;
  Array.to_list context.h |> List.map (Printf.sprintf "%08lx") |> String.concat ""

let sha256_string value =
  let context = initial () in
  update context value 0 (String.length value);
  finish context

let sha256_file path =
  try
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () ->
        let context = initial () in
        let buffer = Bytes.create 65536 in
        let rec loop () =
          let read = input channel buffer 0 (Bytes.length buffer) in
          if read = 0 then Ok (finish context)
          else begin update context (Bytes.sub_string buffer 0 read) 0 read; loop () end
        in
        loop ())
  with Sys_error message -> Error (`Msg message)

module Content_id = struct
  type t = string
  let valid_hex value =
    String.length value = 64 &&
    String.for_all (function '0'..'9' | 'a'..'f' -> true | _ -> false) value
  let of_string content = "sha256:" ^ sha256_string content
  let parse value =
    if String.length value = 71 && String.sub value 0 7 = "sha256:" &&
       valid_hex (String.sub value 7 64)
    then Ok value else Error "content ID must be sha256:<64 lowercase hex>"
  let to_string value = value
  let equal = String.equal
end
