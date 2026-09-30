let root=Sys.argv.(1);;
let read p=let c=open_in_bin p in let s=really_input_string c(in_channel_length c)in close_in c;s;;
let write p s=let c=open_out_bin p in output_string c s;close_out c;;
let before="    Report(id, destination, outcome, reply) ->\n      update(\n        state,\n        peer.report_delivery(state.peer, id, destination, outcome),\n        reply,\n      )";;
let after="    Report(id, destination, outcome, reply) -> {\n      let operation = peer.report_delivery(state.peer, id, destination, outcome)\n      case operation { Ok(_) -> process.sleep(1100) Error(_) -> Nil }\n      update(state, operation, reply)\n    }";;
let replace text src dst=let n=String.length src in let hits=ref []in for i=0 to String.length text-n do if String.sub text i n=src then hits:=i::!hits done;match !hits with[i]->String.sub text 0 i^dst^String.sub text(i+n)(String.length text-i-n)|_->failwith "exact fault source mismatch";;
let p=root^"/src/cepaf_gleam/crdt/mesh_peer_actor.gleam"in write p(replace(read p)before after);;
write(root^"/test/mesh_zenoh_live_test.gleam")"import mesh_zenoh_test\npub fn main() { mesh_zenoh_test.run_delayed_report_fault() }\n";;
if Array.length Sys.argv=3 && Sys.argv.(2)="red"then write(root^"/src/cepaf_gleam/crdt/mesh_zenoh_transport.gleam")(read "/tmp/ev-transport-green8/package/src/cepaf_gleam/crdt/mesh_zenoh_transport.gleam");;
