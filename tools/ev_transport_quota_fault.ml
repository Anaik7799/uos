(* Synthetic initial counter boundary; never a production state/admission. *)
let root=Sys.argv.(1);;
let read p=let c=open_in_bin p in let s=really_input_string c(in_channel_length c)in close_in c;s;;
let write p s=let c=open_out_bin p in output_string c s;close_out c;;
let replace text src dst=let n=String.length src in let hits=ref []in for i=0 to String.length text-n do if String.sub text i n=src then hits:=i::!hits done;match !hits with[i]->String.sub text 0 i^dst^String.sub text(i+n)(String.length text-i-n)|_->failwith "exact fault source mismatch";;
let path=root^"/src/cepaf_gleam/crdt/mesh_zenoh_transport.gleam"in write path(replace(read path)"Stats(0, 0, 0, None, False, False, None, None)""Stats(255, 0, 0, None, False, False, None, None)");;
write(root^"/test/mesh_zenoh_live_test.gleam")"import mesh_zenoh_test\npub fn main() { mesh_zenoh_test.quota_boundary_test() }\n";;
