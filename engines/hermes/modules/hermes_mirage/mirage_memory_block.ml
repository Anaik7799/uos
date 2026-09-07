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

let read t sector_start buffers =
  if not t.connected then Error `Disconnected
  else
    let rec loop idx = function
      | [] -> Ok ()
      | buf :: rest ->
          if idx >= t.size_sectors then
            Error (`Read_error "out of bounds sector read")
          else begin
            begin match Hashtbl.find_opt t.storage idx with
            | Some data ->
                let len = min (Bytes.length buf) (Bytes.length data) in
                Bytes.blit data 0 buf 0 len
            | None ->
                Bytes.fill buf 0 (Bytes.length buf) '\000'
            end;
            loop (Int64.add idx 1L) rest
          end
    in
    loop sector_start buffers

let write t sector_start buffers =
  if not t.connected then Error `Disconnected
  else
    let rec loop idx = function
      | [] -> Ok ()
      | buf :: rest ->
          if idx >= t.size_sectors then
            Error (`Write_error "out of bounds sector write")
          else begin
            let copy = Bytes.copy buf in
            Hashtbl.replace t.storage idx copy;
            loop (Int64.add idx 1L) rest
          end
    in
    loop sector_start buffers
