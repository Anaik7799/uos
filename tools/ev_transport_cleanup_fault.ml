let root=Sys.argv.(1);;
let read p=let c=open_in_bin p in let s=really_input_string c(in_channel_length c)in close_in c;s;;
let write p s=let c=open_out_bin p in output_string c s;close_out c;;
let replace text src dst=let n=String.length src in let hits=ref []in for i=0 to String.length text-n do if String.sub text i n=src then hits:=i::!hits done;match !hits with[i]->String.sub text 0 i^dst^String.sub text(i+n)(String.length text-i-n)|_->failwith "exact fault source mismatch";;
let path=root^"/src/cepaf_gleam/crdt/mesh_zenoh_http.gleam"in let src=read path in write path(replace src "  let deadline = now(Millisecond) + timeout_ms" "  use _ <- result.try(Error(CleanupUnconfirmed))\n  let deadline = now(Millisecond) + timeout_ms");;
write(root^"/test/mesh_zenoh_live_test.gleam")"import mesh_zenoh_test\npub fn main() { mesh_zenoh_test.run_cleanup_halt_fault() }\n";;
if Array.length Sys.argv=3 && Sys.argv.(2)="red"then write(root^"/src/cepaf_gleam/crdt/mesh_zenoh_transport.gleam")(read "/tmp/ev-transport-green14/package/src/cepaf_gleam/crdt/mesh_zenoh_transport.gleam");;
