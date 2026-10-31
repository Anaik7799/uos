(* One framed storage request; the reviewed launcher supplies the DB path.
   No shell, task authority, default production location, or self-retry.
   Run only beneath the pinned process-group guardian; SQLite C calls cannot
   be preempted by an inline OCaml wall-clock check. *)
module Store=Symbiosis_check_receipts
let emit json =
  let body=Yojson.Safe.to_string json in
  let body=if String.length body<=Store.max_response_bytes then body
    else Yojson.Safe.to_string(Store.hold_json Store.Resource_bound) in
  let header=Bytes.create 4 and n=String.length body in
  for i=0 to 3 do Bytes.set header i (Char.chr((n lsr ((3-i)*8))land 255)) done;
  output_bytes stdout header;output_string stdout body;flush stdout
(* Read the one-byte EOF sentinel without admitting any trailing byte. *)
let framed_request () =
  let header=Bytes.create 4 in
  really_input stdin header 0 4;
  let n=ref 0L in
  for i=0 to 3 do n:=Int64.logor(Int64.shift_left !n 8)(Int64.of_int(Char.code(Bytes.get header i)))done;
  if !n<=0L || !n>Int64.of_int Store.max_request_bytes then Error Store.Invalid_request
  else let body=Bytes.create(Int64.to_int !n)in really_input stdin body 0(Bytes.length body);
    match input_char stdin with
    |_->Error Store.Invalid_request
    |exception End_of_file->Store.decode_request(Bytes.to_string body)
let main () =
  if Array.length Sys.argv<>2 then Store.hold_json Store.Invalid_request else
  match framed_request() with
  |Error e->Store.hold_json e
  |Ok request->match Store.open_store ~path:Sys.argv.(1)()with
    |Error e->Store.hold_json e
    |Ok store->
      let result=try Store.execute store request with ex->
        let _=Store.close store in raise ex in
      let closed=Store.close store in
      match result,closed with
      |Ok json,Ok()->json|Error e,_->Store.hold_json e|_,Error _->Store.hold_json Store.Commit_unknown
let () =
  set_binary_mode_in stdin true;set_binary_mode_out stdout true;
  try emit(main()) with
  |End_of_file->emit(Store.hold_json Store.Invalid_request)
  |Unix.Unix_error _|Sys_error _->emit(Store.hold_json Store.Store_unavailable)
  |Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _
  |Sqlite3.RangeError _|Sqlite3.DataTypeError _->emit(Store.hold_json Store.Store_unavailable)
