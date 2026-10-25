//// Shared bounded source for declared mesh configuration; never deployment evidence.
import cepaf_gleam/config/mesh_config as mesh
import cepaf_gleam/harness/telegram_store_codec as strict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type Declaration { Declaration(source: String, config: mesh.MeshConfig) }
pub fn configuration(d: Declaration) { d.config }
pub fn source(d: Declaration) { d.source }
@external(erlang, "cepaf_gleam_ffi", "get_env")
fn env(key: String) -> Result(String, Nil)
fn require(valid: Bool) { case valid { True -> Ok(Nil) False -> Error("mesh_configuration_invalid") } }
pub fn load() -> Result(Declaration, String) {
  from_environment(case env("UOS_MESH_CONFIG_JSON") { Ok(s) -> Some(s) Error(_) -> None })
}
pub fn from_environment(raw: Option(String)) -> Result(Declaration, String) {
  use #(source, config) <- result.try(case raw {
    None -> Ok(#("compiled_default", mesh.default_mesh_config()))
    Some(s) -> decode(s) |> result.map(fn(c) { #("configured", c) })
  })
  use _ <- result.try(require(valid(config)))
  Ok(Declaration(source, config))
}
fn object(value: strict.StrictJsonValue, keys: List(String)) {
  case value {
    strict.JsonObject(fields) -> {
      use _ <- result.try(require(list.length(fields) == list.length(keys)
        && list.all(fields, fn(p) { list.contains(keys, p.0) })))
      Ok(fields)
    }
    _ -> Error("mesh_configuration_invalid")
  }
}
fn field(fields, key) { list.key_find(fields, key) |> result.replace_error("mesh_configuration_invalid") }
fn text(value) { case value { strict.JsonString(s) -> Ok(s) _ -> Error("mesh_configuration_invalid") } }
fn integer(value) { case value { strict.JsonInt(n) -> Ok(n) _ -> Error("mesh_configuration_invalid") } }
fn number(value) {
  case value { strict.JsonFloat(n) -> Ok(n) strict.JsonInt(n) -> Ok(int.to_float(n))
    _ -> Error("mesh_configuration_invalid") }
}
fn text_field(fields, key) { use v <- result.try(field(fields,key)) text(v) }
fn int_field(fields, key) { use v <- result.try(field(fields,key)) integer(v) }
fn array(value, max, decoder) {
  case value {
    strict.JsonArray(values) -> {
      use _ <- result.try(require(list.length(values) <= max))
      list.try_map(values, decoder)
    }
    _ -> Error("mesh_configuration_invalid")
  }
}
fn container(value) {
  use f <- result.try(object(value, ["name","image","port","health_check","cpu_limit","memory_mb"]))
  use name <- result.try(text_field(f,"name"))
  use image <- result.try(text_field(f,"image"))
  use port <- result.try(int_field(f,"port"))
  use health <- result.try(text_field(f,"health_check"))
  use cpu_raw <- result.try(field(f,"cpu_limit"))
  use cpu <- result.try(number(cpu_raw))
  use memory <- result.try(int_field(f,"memory_mb"))
  Ok(mesh.ContainerSpec(name,image,port,health,cpu,memory))
}
fn network(value) {
  use f <- result.try(object(value, ["name","subnet","driver"]))
  use name <- result.try(text_field(f,"name"))
  use subnet <- result.try(text_field(f,"subnet"))
  use driver <- result.try(text_field(f,"driver"))
  Ok(mesh.NetworkSpec(name,subnet,driver))
}
fn volume(value) {
  use f <- result.try(object(value, ["name","mount_path","size_mb"]))
  use name <- result.try(text_field(f,"name"))
  use path <- result.try(text_field(f,"mount_path"))
  use size <- result.try(int_field(f,"size_mb"))
  Ok(mesh.VolumeSpec(name,path,size))
}
pub fn decode(raw: String) -> Result(mesh.MeshConfig, String) {
  use _ <- result.try(require(string.byte_size(raw) > 0 && string.byte_size(raw) <= 65536))
  use tree <- result.try(strict.parse_strict_json(raw) |> result.replace_error("mesh_configuration_invalid"))
  use f <- result.try(object(tree, ["containers","networks","volumes","quorum_size"]))
  use cs <- result.try(field(f,"containers"))
  use containers <- result.try(array(cs,64,container))
  use ns <- result.try(field(f,"networks"))
  use networks <- result.try(array(ns,16,network))
  use vs <- result.try(field(f,"volumes"))
  use volumes <- result.try(array(vs,64,volume))
  use quorum <- result.try(int_field(f,"quorum_size"))
  Ok(mesh.MeshConfig(containers,networks,volumes,quorum))
}
fn bounded_text(s: String) -> Bool {
  s != "" && string.byte_size(s) <= 256
  && list.all(string.to_utf_codepoints(s), fn(c) { let n=string.utf_codepoint_to_int(c) n >= 32 && n <= 126 })
}
fn identifier(s: String) -> Bool {
  let alphabet="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  string.byte_size(s) <= 64 && case string.to_graphemes(s) {
    [] -> False
    [first,..rest] -> string.contains(alphabet,first)
      && list.all(rest,fn(c) { string.contains(alphabet <> "._-",c) })
  }
}
fn canonical_int(s: String, low: Int, high: Int) -> Result(Int, Nil) {
  use n <- result.try(int.parse(s))
  case n >= low && n <= high && int.to_string(n) == s { True -> Ok(n) False -> Error(Nil) }
}
fn pow2(n: Int) -> Int { case n { 0 -> 1 _ -> 2 * pow2(n-1) } }
pub fn subnet_valid(s: String) -> Bool {
  let parsed = {
    use #(host,prefix) <- result.try(case string.split(s,"/") {
      [h,p] -> Ok(#(h,p)) _ -> Error(Nil) })
    use bits <- result.try(canonical_int(prefix,0,32))
    use octets <- result.try(list.try_map(string.split(host,"."),fn(p) { canonical_int(p,0,255) }))
    case octets {
      [a,b,c,d] -> Ok({a*16777216+b*65536+c*256+d} % pow2(32-bits) == 0)
      _ -> Error(Nil)
    }
  }
  result.unwrap(parsed,False)
}
fn unique(names: List(String)) -> Bool { list.length(list.unique(names)) == list.length(names) }
pub fn valid(c: mesh.MeshConfig) -> Bool {
  c.containers != [] && list.length(c.containers) <= 64
  && list.length(c.networks) <= 16 && list.length(c.volumes) <= 64
  && c.quorum_size >= 1 && c.quorum_size <= list.length(c.containers)
  && unique(list.map(c.containers,fn(x) { x.name }))
  && unique(list.map(c.networks,fn(x) { x.name }))
  && unique(list.map(c.volumes,fn(x) { x.name }))
  && unique(list.map(c.networks,fn(x) { x.subnet }))
  && list.all(c.containers,fn(x) { identifier(x.name) && bounded_text(x.image)
    && bounded_text(x.health_check) && x.port >= 1 && x.port <= 65535
    && x.cpu_limit >. 0.0 && x.cpu_limit <=. 32.0 && x.memory_mb >= 1 && x.memory_mb <= 65536 })
  && list.all(c.networks,fn(x) { identifier(x.name) && identifier(x.driver) && subnet_valid(x.subnet) })
  && list.all(c.volumes,fn(x) { identifier(x.name) && bounded_text(x.mount_path)
    && string.starts_with(x.mount_path,"/") && !list.contains(string.split(x.mount_path,"/"),"..")
    && x.size_mb >= 1 && x.size_mb <= 1048576 })
  && mesh.is_valid(c)
}
pub fn summary(value: Result(Declaration,String)) -> json.Json {
  case value {
    Error(_) -> json.object([#("status",json.string("unavailable")),#("valid",json.bool(False)),
      #("reason",json.string("mesh_configuration_invalid")),#("deployment_confirmed",json.bool(False))])
    Ok(d) -> json.object([#("status",json.string("declared")),#("source",json.string(d.source)),
      #("valid",json.bool(True)),#("deployment_confirmed",json.bool(False)),
      #("containers",json.int(list.length(d.config.containers))),
      #("networks",json.int(list.length(d.config.networks))),
      #("volumes",json.int(list.length(d.config.volumes))),
      #("quorum_size",json.int(d.config.quorum_size)),
      #("total_cpu",json.float(mesh.total_cpu_allocation(d.config))),
      #("total_memory_mb",json.int(mesh.total_memory_allocation(d.config)))])
  }
}
