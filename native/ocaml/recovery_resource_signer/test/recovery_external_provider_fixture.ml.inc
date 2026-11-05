
(* COMPILE-TIME TEST ONLY. Each provider PROCESS alone holds one deliberately
   public R/I vector. Never appended to the production module or client worker.
   This is a local-purpose protocol demonstration, not HSM/custody provisioning. *)
let as_hex s=String.concat""(List.init(String.length s)(fun i->Printf.sprintf"%02x"(Char.code s.[i])))
let fixture_provider role key socket_path manifest_path manifest_sha=
 let listen=Unix.socket~cloexec:true Unix.PF_UNIX Unix.SOCK_STREAM 0 in
 Fun.protect~finally:(fun()->Unix.close listen)(fun()->
 Unix.bind listen(Unix.ADDR_UNIX socket_path);Unix.chmod socket_path 0o600;
 Unix.listen listen 2;Unix.set_nonblock listen;
 let st=Unix.lstat socket_path in
 let provider={role;manifest_path;manifest_sha;socket={path=socket_path;device=st.Unix.st_dev;inode=st.Unix.st_ino;uid=Unix.geteuid()}}in
 let lifetime=Int64.add(Mtime_clock.now_ns())60000000000L in
 for _=1 to 2 do
 wait listen false lifetime;
 let fd,_=Unix.accept~cloexec:true listen in
 Fun.protect~finally:(fun()->Unix.close fd)(fun()->
 Unix.set_nonblock fd;let until=io_deadline()in let body=receive_frame fd until in
 let j=parse 4096 body in
 closed j["schema";"operation";"intent_id";"manifest_sha256";"request_sha256";"capability_sha256";"resource_sha256";"message_sha256";"kernel_review";"kernel_issuer";"resource_review"];
 require(text j"schema"="uos.recovery.external-provider-request.v1")"FIXTURE_PROVIDER_REFUSED";
 let raw=Yojson.Basic.to_string(`Assoc[
  "schema",`String"uos.recovery.native-signing.v2";"operation",`String(text j"operation");"intent_id",`String(text j"intent_id");
  "kernel_review",`String(text j"kernel_review");"kernel_issuer",`String(text j"kernel_issuer");"resource_review",`String(text j"resource_review")])in
 let request=ok(request_of_json raw)in let prepared=ok(prepare_bound provider request)in
 (* No message/key reference/path is received. Reconstruct from own compiled
    manifest and independently compare every request field before signing. *)
 require(external_request request prepared=body)"FIXTURE_PROVIDER_BINDING";
 let public=as_hex(Mirage_crypto_ec.Ed25519.pub_to_octets(Mirage_crypto_ec.Ed25519.pub_of_priv key))in
 require(public=prepared.public)"FIXTURE_PROVIDER_ROLE_KEY";
 let signature=as_hex(Mirage_crypto_ec.Ed25519.sign~key prepared.message)in
 prepared.check_signature signature;prepared.recheck();
 let reply=Yojson.Basic.to_string(`Assoc[
  "schema",`String"uos.recovery.external-provider-response.v1";"operation",`String(op_name request.operation);"intent_id",`String request.intent;
  "provider_request_sha256",`String(K.sha256 body);"message_sha256",`String(K.sha256 prepared.message);"signature_hex",`String signature;
  "authority",`String"NONE";"admitted",`Bool false])in
 send_frame fd until reply)
 done;
 print_endline("PROVIDER_TWO_PURPOSE_CALLS_COMPLETED key_role="^(if role=Reviewer then"reviewer"else"issuer")^" authority=NONE"))
