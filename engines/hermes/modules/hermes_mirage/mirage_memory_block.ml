(** In-Memory Sector-Level Block Device satisfying MIRAGE_BLOCK (EV-87) *)

type t = {
  mutable connected : bool;
  sector_size : int;
  size_sectors : int64;
  storage : (int64, bytes) Hashtbl.t;
}

let create ?(sector_size = 512) size_sectors =
  if sector_size <= 0 || (sector_size land (sector_size - 1)) <> 0 then
    Error "sector size must be a positive power of 2"
  else if size_sectors <= 0L then
    Error "size in sectors must be strictly positive"
  else
    Ok {
      connected = true;
      sector_size;
      size_sectors;
      storage = Hashtbl.create 128;
    }

let get_info t =
  {
    Mirage_signatures.read_write = true;
    sector_size = t.sector_size;
    size_sectors = t.size_sectors;
  }

let disconnect t =
  t.connected <- false;
  Hashtbl.clear t.storage

let validate_request t sector_start buffers make_error =
  if sector_start < 0L then
    Error (make_error "sector start must be non-negative")
  else if sector_start > t.size_sectors then
    Error (make_error "sector start is out of bounds")
  else if List.exists (fun buffer -> Bytes.length buffer <> t.sector_size) buffers then
    Error (make_error "each buffer must contain exactly one sector")
  else
    match buffers with
    | [] -> Ok ()
    | _ ->
        let sector_count = Int64.of_int (List.length buffers) in
        if sector_start >= t.size_sectors ||
           sector_count > Int64.sub t.size_sectors sector_start then
          Error (make_error "out of bounds sector range")
        else
          Ok ()

let read t sector_start buffers =
  if not t.connected then Error `Disconnected
  else match validate_request t sector_start buffers (fun message -> `Read_error message) with
  | Error error -> Error error
  | Ok () ->
    let rec loop idx = function
      | [] -> Ok ()
      | buf :: rest ->
          begin match Hashtbl.find_opt t.storage idx with
          | Some data -> Bytes.blit data 0 buf 0 t.sector_size
          | None -> Bytes.fill buf 0 t.sector_size '\000'
          end;
          loop (Int64.add idx 1L) rest
    in
    loop sector_start buffers

let write t sector_start buffers =
  if not t.connected then Error `Disconnected
  else match validate_request t sector_start buffers (fun message -> `Write_error message) with
  | Error error -> Error error
  | Ok () ->
    let rec loop idx = function
      | [] -> Ok ()
      | buf :: rest ->
          Hashtbl.replace t.storage idx (Bytes.copy buf);
          loop (Int64.add idx 1L) rest
    in
    loop sector_start buffers
