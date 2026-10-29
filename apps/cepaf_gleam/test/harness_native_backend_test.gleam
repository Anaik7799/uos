//// INERT pure policy tests plus isolated-node registry probe entrypoints.
//// Stateful probes MUST each run in a fresh dedicated BEAM; no reset API exists.
import cepaf_gleam/harness/native_backend as backend
import cepaf_gleam/harness/development as dev
import gleam/bit_array
import gleam/io
import cepaf_gleam/harness/value
import gleam/erlang/process.{type Pid}
import gleam/list
import gleeunit/should
const path = "/nix/store/mmycwn1v7bvpjgl0hxvbazxrqwjwn335-uos-sa-plan-main-cfe06ec3"
fn profile() -> value.Value {
  value.Object([
    #("mode",value.Text("host_immutable_nix")),
    #("store_path",value.Text(path)),
    #("sha256",value.Text(backend.expected_sha256)),
    #("bytes",value.Integer(backend.expected_bytes)),
  ])
}
fn document(p:value.Value) -> value.Value {
  value.Object([#("role",value.Text("development")),
    #("candidate_binding",value.Object([#("native_backend",p)]))])
}
fn observed()->backend.FileObservation {
  backend.FileObservation(True,False,0,365,backend.expected_bytes,
    backend.expected_sha256,True,[
      backend.DirectoryObservation("/nix",True,0,493,False),
      backend.DirectoryObservation("/nix/store",True,0,1021,False),
    ])
}
pub fn positive_exact_identity_test() {
  backend.choose(document(profile()))|>should.equal(Ok(backend.HostImmutableNix(path)))
  backend.observation_valid(path,observed())|>should.be_true
}
pub fn exact_store_leaf_path_test() {
  list.each([
    "/tmp/mmycwn1v7bvpjgl0hxvbazxrqwjwn335-uos-sa-plan-main-cfe06ec3",
    path<>"/child",path<>"/../other",path<>"\u{0000}",
    "/nix/store/oooooooooooooooooooooooooooooooo-uos-sa-plan-main-cfe06ec3",
    "/nix/store/mmycwn1v7bvpjgl0hxvbazxrqwjwn335-foreign",
  ],fn(p){backend.path_valid(p)|>should.be_false})
}
pub fn explicit_invalid_profile_never_falls_back_test() {
  list.each([
    #("mode",value.Text("arbitrary_env")),#("store_path",value.Text("/tmp/foreign")),
    #("sha256",value.Text("0000000000000000000000000000000000000000000000000000000000000000")),
    #("bytes",value.Integer(1)),#("mode",value.Null),
  ],fn(m){backend.choose(document(value.set(profile(),m.0,m.1)))|>should.be_error})
  backend.choose(value.Object([#("candidate_binding",value.Null)]))|>should.be_error
  backend.choose(value.set(document(profile()),"role",value.Text("production")))|>should.be_error
}
pub fn file_identity_mutants_test() {
  let o=observed()
  list.each([
    backend.FileObservation(..o,regular:False),
    backend.FileObservation(..o,symlink:True),
    backend.FileObservation(..o,uid:1000),
    backend.FileObservation(..o,mode:493),
    backend.FileObservation(..o,mode:292),
    backend.FileObservation(..o,bytes:1),
    backend.FileObservation(..o,sha256:"bad"),
    backend.FileObservation(..o,stable:False),
    backend.FileObservation(..o,ancestors:[]),
    backend.FileObservation(..o,ancestors:[
      backend.DirectoryObservation("/nix",True,0,493,False),
      backend.DirectoryObservation("/nix/store",True,1000,1021,False),
    ]),
    backend.FileObservation(..o,ancestors:[
      backend.DirectoryObservation("/nix",True,0,493,False),
      backend.DirectoryObservation("/nix/store",True,0,1023,False),
    ]),
  ],fn(m){backend.observation_valid(path,m)|>should.be_false})
}
pub fn no_tool_argument_override_test() {
  let legacy=value.Object([#("tool_args",document(profile()))])
  backend.choose(legacy)|>should.equal(Ok(backend.Legacy))
  let existing=value.Object([#("candidate_binding",value.Object([
    #("native_cli",value.Object([#("store_path",value.Text(path))])),
  ]))])
  backend.choose(existing)|>should.equal(Ok(backend.Legacy))
}
pub fn legacy_default_test() {
  backend.choose(value.Object([]))|>should.equal(Ok(backend.Legacy))
}


pub fn qualified_standard_store_ancestor_test() {
  backend.ancestor_valid(backend.DirectoryObservation("/nix/store",True,0,1021,False))|>should.be_true
  list.each([
    backend.DirectoryObservation("/nix/store",True,0,509,False), //0775, no sticky
    backend.DirectoryObservation("/nix/store",True,0,1023,False), //01777, world write
    backend.DirectoryObservation("/nix/store",True,0,1021,True), //current subject writable
    backend.DirectoryObservation("/nix/store",True,1000,1021,False),
    backend.DirectoryObservation("/other",True,0,1021,False),
    backend.DirectoryObservation("/nix",True,0,1021,False),
    backend.DirectoryObservation("/nix/store",False,0,1021,False),
  ],fn(a){backend.ancestor_valid(a)|>should.be_false})
}
@external(erlang,"erlang","spawn")
fn spawn_pid(work:fn()->Nil)->Pid
pub fn gleam_transition_owner_identity_and_poison_test() {
  let owner=backend.current_owner()
  let foreign=spawn_pid(fn(){Nil})
  let d=backend.expected_sha256
  let pending=backend.Pending(d,owner)
  backend.reserve_transition(backend.Absent,d,owner)|>should.equal(Ok(pending))
  backend.reserve_transition(pending,d,owner)|>should.be_error
  backend.reserve_transition(backend.Absent,"bad",owner)|>should.be_error
  backend.commit_transition(pending,d,path,foreign)|>should.be_error
  backend.poison_transition(pending,d,foreign)|>should.be_error
  backend.commit_transition(pending,d,"/tmp/foreign",owner)|>should.be_error
  let ready=backend.Ready(d,path)
  backend.commit_transition(pending,d,path,owner)|>should.equal(Ok(ready))
  backend.commit_transition(ready,d,path,owner)|>should.equal(Ok(ready))
  backend.commit_transition(ready,d,backend.canonical,owner)|>should.be_error
  backend.reserve_transition(ready,d,owner)|>should.equal(Ok(ready))
  backend.reserve_transition(ready,"0000000000000000000000000000000000000000000000000000000000000000",owner)|>should.be_error
  backend.poison_transition(pending,d,owner)|>should.equal(Ok(backend.Failed(d)))
  backend.selected_from(backend.Failed(d))|>should.be_error
  backend.selected_from(pending)|>should.be_error
  backend.selected_from(backend.Absent)|>should.equal(Ok(backend.canonical))
  backend.selected_from(ready)|>should.equal(Ok(path))
}


// Standard EUnit tests invoke only these two fixed, tracked entrypoints.
// No caller/tool-provided eval, executable, argv or backend override.
@external(erlang,"ecology_capability_ffi","uos_root")
fn candidate_root()->String
@external(erlang,"ecology_capability_ffi","run_bounded")
fn run_fixed(executable:String,args:List(String),timeout_ms:Int)->Result(#(Int,BitArray),String)

fn child_eval(entry:String)->String {
  let app=candidate_root()<>"/apps/cepaf_gleam/build"
  let paths="filelib:wildcard(\""<>app<>"/dev/erlang/*/ebin\") ++ "
    <>"filelib:wildcard(\""<>app<>"/test/erlang/*/ebin\") ++ code:get_path()"
  "code:set_path("<>paths<>"), harness_native_backend_test:"<>entry<>"(), halt(0)."
}
fn assert_fixed_child(entry:String,expected:String) {
  let assert Ok(#(0,bytes))=run_fixed(
    dev.root<>"/toolchains/nix-profile/bin/erl",
    ["+S","2:2","+A","2","-noinput","-noshell","-eval",child_eval(entry)],
    10_000,
  )
  let assert Ok(output)=bit_array.to_string(bytes)
  output|>should.equal(expected<>"\n")
}
pub fn fresh_node_registry_idempotence_owner_rebind_and_child_visibility_test() {
  assert_fixed_child("registry_laws_child_main","REGISTRY_LAWS_PASS")
}
pub fn fresh_node_failed_startup_never_falls_back_test() {
  assert_fixed_child("registry_failed_startup_child_main","REGISTRY_FAILED_STARTUP_PASS")
}
pub fn registry_laws_child_main() {
  let d=backend.expected_sha256
  backend.selected_path()|>should.equal(Ok(backend.canonical))
  backend.registry_reserve(d)|>should.equal(Ok(Nil))
  backend.selected_path()|>should.be_error
  backend.registry_commit(d,path)|>should.equal(Ok(Nil))
  backend.registry_reserve(d)|>should.equal(Ok(Nil))
  backend.registry_commit(d,path)|>should.equal(Ok(Nil))
  let reply=process.new_subject()
  let _ = spawn_pid(fn(){process.send(reply,backend.selected_path())})
  let assert Ok(Ok(child_path))=process.receive(reply,1000)
  child_path|>should.equal(path)
  backend.registry_commit(d,backend.canonical)|>should.be_error
  backend.registry_reserve("0000000000000000000000000000000000000000000000000000000000000000")|>should.be_error
  backend.selected_path()|>should.equal(Ok(path))
  io.println("REGISTRY_LAWS_PASS")
}
pub fn registry_failed_startup_child_main() {
  let d=backend.expected_sha256
  backend.registry_reserve(d)|>should.equal(Ok(Nil))
  backend.registry_poison(d)|>should.equal(Ok(Nil))
  backend.selected_path()|>should.be_error
  backend.registry_reserve(d)|>should.be_error
  io.println("REGISTRY_FAILED_STARTUP_PASS")
}

