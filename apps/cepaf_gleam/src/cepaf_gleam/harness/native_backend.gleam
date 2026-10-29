//// INERT dedicated development BEAM selector; no admission dependency/cycle.
//// initialize is called only AFTER admission.load, before serving any tools.
import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import gleam/erlang/process.{type Pid}
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const canonical = "/home/an/NAS-setup/uos/engines/hermes/_build/default/modules/sa_plan/test/sa_plan_main.exe"
pub const expected_sha256 = "cfe06ec3e54a6cca54e59d8f521d8ae903f0c8e4703c1d447fcf3fff5534cf91"
pub const expected_bytes = 42_344_784
pub const suffix = "-uos-sa-plan-main-cfe06ec3"
const root = "/home/an/NAS-setup/uos"

pub type FileObservation {
  FileObservation(regular: Bool, symlink: Bool, uid: Int, mode: Int,
    bytes: Int, sha256: String, stable: Bool,
    ancestors: List(DirectoryObservation))
}
pub type DirectoryObservation { DirectoryObservation(path: String, directory: Bool, uid: Int, mode: Int, writable: Bool) }
pub type RegistryState { Absent Pending(String, Pid) Ready(String, String) Failed(String) }
pub type Choice { Legacy HostImmutableNix(String) }

@external(erlang, "harness_native_backend_ffi", "read_state")
fn read_state() -> RegistryState
@external(erlang, "harness_native_backend_ffi", "cas_state")
fn cas_state(expected: RegistryState, replacement: RegistryState) -> Result(Bool,String)
@external(erlang, "erlang", "self")
pub fn current_owner() -> Pid
@external(erlang, "harness_native_backend_ffi", "observe")
fn observe(path: String,max_bytes: Int,timeout_ms: Int) -> Result(FileObservation,String)

fn digest_valid(d:String)->Bool {
  string.byte_size(d)==64 && list.all(string.to_graphemes(d),fn(c){
    string.contains("0123456789abcdef",c)
  })
}
pub fn reserve_transition(s:RegistryState,d:String,owner:Pid)->Result(RegistryState,String) {
  use _<-result.try(require(digest_valid(d),"backend_grant_digest"))
  case s {
    Absent -> Ok(Pending(d,owner))
    Ready(existing,_) if existing==d -> Ok(s)
    Pending(_,_) -> Error("backend_initialization_in_progress")
    Failed(_) -> Error("backend_initialization_failed")
    Ready(_,_) -> Error("backend_rebind_forbidden")
  }
}
pub fn commit_transition(s:RegistryState,d:String,path:String,owner:Pid)->Result(RegistryState,String) {
  use _<-result.try(require(digest_valid(d) && {path==canonical || path_valid(path)},"backend_commit_identity"))
  case s {
    Pending(existing,held) if existing==d && held==owner -> Ok(Ready(d,path))
    Ready(existing,selected) if existing==d && selected==path -> Ok(s)
    _ -> Error("backend_commit_binding")
  }
}
pub fn poison_transition(s:RegistryState,d:String,owner:Pid)->Result(RegistryState,String) {
  case s {
    Pending(existing,held) if existing==d && held==owner -> Ok(Failed(d))
    Ready(existing,_) if existing==d -> Ok(s)
    _ -> Error("backend_poison_binding")
  }
}
fn update(transition:fn(RegistryState)->Result(RegistryState,String))->Result(Nil,String) {
  let before=read_state()
  use after<-result.try(transition(before))
  use changed<-result.try(cas_state(before,after))
  require(changed,"backend_state_contention")
}
pub fn registry_reserve(d:String)->Result(Nil,String) {
  update(fn(s){reserve_transition(s,d,current_owner())})
}
pub fn registry_commit(d:String,path:String)->Result(Nil,String) {
  update(fn(s){commit_transition(s,d,path,current_owner())})
}
pub fn registry_poison(d:String)->Result(Nil,String) {
  update(fn(s){poison_transition(s,d,current_owner())})
}
pub fn selected_from(s:RegistryState)->Result(String,String) {
  case s {
    Absent -> Ok(canonical)
    Ready(_,path) -> Ok(path)
    Pending(_,_) -> Error("backend_initializing")
    Failed(_) -> Error("backend_initialization_failed")
  }
}

pub fn path_valid(path: String) -> Bool {
  case string.starts_with(path,"/nix/store/") {
    False -> False
    True -> {
      let leaf = string.drop_start(path,11)
      string.byte_size(leaf)==32+string.byte_size(suffix)
      && string.ends_with(leaf,suffix)
      && list.all(string.to_graphemes(string.slice(leaf,0,32)),fn(c){
        string.contains("0123456789abcdfghijklmnpqrsvwxyz",c)
      })
    }
  }
}
pub fn choose(document: value.Value) -> Result(Choice,String) {
  case value.get(document,"candidate_binding") {
    Error(_) -> Ok(Legacy)
    Ok(binding) -> case binding {
      value.Object(_) -> case value.get(binding,"native_backend") {
        Error(_) -> Ok(Legacy)
        Ok(profile) -> {
          use _<-result.try(equal(document,"role",value.Text("development")))
          use _<-result.try(equal(profile,"mode",value.Text("host_immutable_nix")))
          use path<-result.try(text(profile,"store_path"))
          use _<-result.try(require(path_valid(path),"backend_store_path"))
          use _<-result.try(equal(profile,"sha256",value.Text(expected_sha256)))
          use _<-result.try(equal(profile,"bytes",value.Integer(expected_bytes)))
          Ok(HostImmutableNix(path))
        }
      }
      _ -> Error("candidate_binding_object_required")
    }
  }
}
pub fn observation_valid(path: String, o: FileObservation) -> Bool {
  path_valid(path) && o.regular && !o.symlink && o.uid==0
  && o.mode==365 // exact0555: executable, no write bits
  && o.bytes==expected_bytes && o.sha256==expected_sha256 && o.stable
  && list.map(o.ancestors,fn(a){a.path})==["/nix","/nix/store"]
  && list.all(o.ancestors,ancestor_valid)
}
pub fn ancestor_valid(a:DirectoryObservation)->Bool {
  let group_write = a.mode / 16 % 2 == 1
  let world_write = a.mode / 2 % 2 == 1
  let sticky = a.mode / 512 % 2 == 1
  a.directory && a.uid==0 && !world_write && {
    case a.path {
      "/nix" -> !group_write
      "/nix/store" -> !group_write || {sticky && !a.writable}
      _ -> False
    }
  }
}

fn prepare(path: String, digest: String) -> Result(String,String) {
  use body<-result.try(files.read(root,path))
  use _<-result.try(require(files.digest(body)==digest,"admitted_grant_bytes_changed"))
  use doc<-result.try(json.parse(body,value.decoder())|>result.map_error(fn(_){"invalid_grant_json"}))
  use choice<-result.try(choose(doc))
  case choice {
    Legacy -> Ok(canonical)
    HostImmutableNix(path) -> {
      use observed<-result.try(observe(path,expected_bytes,3000))
      use _<-result.try(require(observation_valid(path,observed),"immutable_backend_identity"))
      Ok(path)
    }
  }
}
pub fn initialize(admitted_grant_path: String, admitted_grant_digest: String) -> Result(Nil,String) {
  // Reserving first prevents explicit failed selection from silently falling back.
  use _<-result.try(registry_reserve(admitted_grant_digest))
  case prepare(admitted_grant_path,admitted_grant_digest) {
    Ok(path) -> registry_commit(admitted_grant_digest,path)
    Error(reason) -> {
      let _ = registry_poison(admitted_grant_digest)
      Error(reason)
    }
  }
}
pub fn selected_path() -> Result(String,String) { selected_from(read_state()) }
fn text(v:value.Value,k:String)->Result(String,String){
  use x<-result.try(value.get(v,k))
  case x {value.Text(s)->Ok(s) _->Error("backend_text:"<>k)}
}
fn equal(v:value.Value,k:String,wanted:value.Value)->Result(Nil,String){
  use got<-result.try(value.get(v,k))
  require(got==wanted,"backend_field:"<>k)
}
fn require(ok:Bool,why:String)->Result(Nil,String){case ok {True->Ok(Nil) False->Error(why)}}
