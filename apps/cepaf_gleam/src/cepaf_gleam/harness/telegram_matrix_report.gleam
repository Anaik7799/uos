//// Actual Matrix client-version observation; does not prove federation health.
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

@external(erlang,"telegram_matrix_http","get")
fn get(host:String,port:Int,path:String,timeout:Int,max_bytes:Int)->Result(String,String)

fn versions_decoder() {
  use versions <- decode.field("versions",decode.list(decode.string))
  use unstable <- decode.optional_field("unstable_features",dict.new(),decode.dict(decode.string,decode.bool))
  decode.success(#(versions,unstable))
}
fn valid_version(version:String)->Bool {
  let parts=string.split(string.drop_start(version,1),".")
  string.byte_size(version)<=32 && {string.starts_with(version,"v") || string.starts_with(version,"r")}
  && list.length(parts)>=2 && list.length(parts)<=4
  && list.all(parts,fn(p){
    string.byte_size(p)>=1 && string.byte_size(p)<=6
    && list.all(string.to_graphemes(p),fn(c){string.contains("0123456789",c)})
  })
}
pub fn project(raw:String)->Result(String,String) {
  use _ <- result.try(case string.byte_size(raw)<=16384 {
    True -> Ok(Nil)
    False -> Error("matrix_payload_refused")
  })
  use pair <- result.try(json.parse(raw,versions_decoder()) |> result.replace_error("matrix_payload_refused"))
  let #(versions,unstable)=pair
  use _ <- result.try(case versions!=[] && list.length(versions)<=64
    && list.length(list.unique(versions))==list.length(versions)
    && list.all(versions,valid_version) && dict.size(unstable)<=256
    && list.all(dict.keys(unstable),fn(k){string.byte_size(k)>0 && string.byte_size(k)<=128}) {
    True -> Ok(Nil)
    False -> Error("matrix_payload_refused")
  })
  Ok(json.object([
    #("schema",json.string("uos.telegram.matrix.v1")),
    #("status",json.string("observed")),
    #("authority",json.string("observation_only")),
    #("runtime_admission",json.string("NOT_GRANTED")),
    #("endpoint",json.string("http://nas-1.tail55d152.ts.net:6167/_matrix/client/versions")),
    #("scope",json.string("matrix_client_versions_endpoint")),
    #("supported_versions",json.array(versions,json.string)),
    #("unstable_feature_count",json.int(dict.size(unstable))),
    #("federation_health",json.string("UNOBSERVED")),
    #("authenticated_operations",json.string("UNOBSERVED")),
  ]) |> json.to_string)
}
pub fn read()->Result(String,String) {
  use raw <- result.try(get("nas-1.tail55d152.ts.net",6167,"/_matrix/client/versions",1500,16384))
  project(raw)
}
