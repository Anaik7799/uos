(* One bounded factual-storage request; trusted launcher DB argv, no defaults.
   Run ONLY below the unchanged reviewed process-group guardian/cgroup. *)
module Store=Ecology_release_grants
let emit json=let body=Yojson.Safe.to_string json in
 let body=if String.length body<=Store.max_response_bytes then body else Yojson.Safe.to_string(Store.hold_json Store.Resource_bound)in
 let h=Bytes.create 4 in for i=0 to 3 do Bytes.set h i(Char.chr((String.length body lsr((3-i)*8))land 255))done;
 output_bytes stdout h;output_string stdout body;flush stdout
let framed_request()=
 let h=Bytes.create 4 in really_input stdin h 0 4;let count=ref 0L in
 for i=0 to 3 do count:=Int64.logor(Int64.shift_left !count 8)(Int64.of_int(Char.code(Bytes.get h i)))done;
 if !count<=0L || !count>Int64.of_int Store.max_request_bytes then Error Store.Invalid_request else
 let body=really_input_string stdin(Int64.to_int !count)in
 match input_char stdin with _->Error Store.Invalid_request|exception End_of_file->Store.decode_request body
let main()=if Array.length Sys.argv<>2 then Store.hold_json Store.Invalid_request else
 match framed_request()with Error e->Store.hold_json e|Ok request->
 match Store.open_store ~path:Sys.argv.(1)()with Error e->Store.hold_json e|Ok store->
 let result=try Store.execute store request with ex->let _=Store.close store in raise ex in
 let closed=Store.close store in
 match result,closed with _,Error _->Store.hold_json Store.Commit_unknown|Ok json,Ok()->json|Error e,Ok()->Store.hold_json e
let ()=set_binary_mode_in stdin true;set_binary_mode_out stdout true;
 try emit(main())with End_of_file->emit(Store.hold_json Store.Invalid_request)
 |Unix.Unix_error _|Sys_error _->emit(Store.hold_json Store.Store_unavailable)
 |Sqlite3.Error _|Sqlite3.SqliteError _|Sqlite3.InternalError _|Sqlite3.RangeError _|Sqlite3.DataTypeError _->emit(Store.hold_json Store.Store_unavailable)
