open! Core
open Result.Let_syntax
module Store = Sa_plan_store
module Bridge = Sa_plan_bridge_protocol
let rejected = "cancellation_target_refused"
type t = { controller : Bridge.t; controller_json : string; fence : int64; job : string }
let token s =
  String.length s > 0 && String.length s <= 240
  && not (String.is_substring s ~substring:"..")
  && String.for_all s ~f:(function
    | 'a'..'z' | 'A'..'Z' | '0'..'9' | '-' | '_' | '.' | '/' | ':' -> true
    | _ -> false)
let decode raw =
  try
    if String.length raw = 0 || String.length raw > 8192
      || not (Stdlib.String.is_valid_utf_8 raw) then Error rejected else
    match Yojson.Safe.from_string raw with
    | `Assoc fields ->
      let keys=["schema";"controller_json";"fencing_token";"target_job_id"] in
      let%bind () = if List.length fields=4 && List.for_all keys ~f:(fun k->
        List.count fields ~f:(fun (key,_)->String.equal key k)=1) then Ok () else Error rejected in
      let text key = match List.Assoc.find fields ~equal:String.equal key with
        | Some (`String s)->Ok s | _->Error rejected in
      let%bind schema=text "schema" in
      let%bind ()=if String.equal schema "uos.sa-plan.cancel-target-request.v1" then Ok () else Error rejected in
      let%bind controller_json=text "controller_json" in
      let%bind controller=Result.map_error (Bridge.decode Lookup controller_json) ~f:(fun _->rejected) in
      let%bind fence_raw=text "fencing_token" in
      let fence=Int64.of_string fence_raw in
      let%bind ()=if Int64.(fence>0L) && String.equal fence_raw (Int64.to_string fence)
        then Ok () else Error rejected in
      let%bind job=text "target_job_id" in
      if token job then Ok {controller;controller_json;fence;job} else Error rejected
    | _->Error rejected
  with _->Error rejected

let int64_json n = `Intlit (Int64.to_string n)
let execute_observed store r ~observe_now =
  try
    Result.map_error (Store.with_transaction store (fun ()->
      let now_ns=observe_now () in
      let%bind ()=if Int64.(now_ns>=0L) then Ok () else Error rejected in
      (* Exact controller/mapping/attempt/expiry binding in the same snapshot. *)
      let%bind _=Bridge.execute store r.controller ~now_ns in
      let fields=Yojson.Safe.from_string r.controller_json |> Yojson.Safe.Util.to_assoc in
      let str k=List.Assoc.find_exn fields ~equal:String.equal k |> Yojson.Safe.Util.to_string in
      let%bind target=Store.inspect_cancellation_target_observed store
        ~mapping_id:(str "mapping_id") ~owner:(str "owner")
        ~lease_id:(str "lease_id") ~fencing_token:r.fence ~target_job_id:r.job
        ~observe_now:(fun ()->now_ns) in
      Ok (`Assoc [
        "schema",`String "uos.sa-plan.cancel-target-response.v1";
        "controller_sha256",`String Digestif.SHA256.(to_hex (digest_string r.controller_json));
        "fencing_token",int64_json r.fence;
        "observed_at_ns",int64_json now_ns;
        "target",`Assoc [
          "job_id",`String target.job_id;
          "worker",`String target.target_worker;
          "attempt",`Int target.target_attempt;
          "lease_until_ns",int64_json target.target_lease_until_ns
        ] ]))) ~f:(fun _->rejected)
  with _->Error rejected
