(* TEST ONLY. NONSECRET deterministic R/I test vectors; no real key storage,
   key generation/export, arbitrary algorithm/message or production route.
   A compiled test fixture is not an authenticated provider. *)
let need b = if not b then failwith "FIXTURE_DATA_REFUSED"
let key role =
 let byte=match role with "reviewer"->'R'|"issuer"->'I'|_->failwith "fixture role" in
 match Mirage_crypto_ec.Ed25519.priv_of_octets(String.make 32 byte)with
 |Ok k->k|Error _->failwith "fixture vector"
let b64 b=Cryptokit.transform_string(Cryptokit.Base64.encode_compact())b
 |>String.map(function '+'->'-'|'/'->'_'|c->c)
 |>fun b->String.concat ""(String.split_on_char '=' b)
let public role=b64(Mirage_crypto_ec.Ed25519.pub_to_octets(Mirage_crypto_ec.Ed25519.pub_of_priv(key role)))
let unb64 b=
 need(String.for_all(function 'a'..'z'|'A'..'Z'|'0'..'9'|'-'|'_'->true|_->false)b);
 let raw=String.map(function '-'->'+'|'_'->'/'|c->c)b in
 let bytes=Cryptokit.transform_string(Cryptokit.Base64.decode())(raw^String.make((4-String.length raw mod 4)mod 4)'=')in
 need(b64 bytes=b);bytes
let text j k=Yojson.Basic.Util.(to_string(member k j))
let closed j keys=match j with `Assoc fs->need(List.map fst fs=keys)|_->failwith "object"
let sha b=Digestif.SHA256.(to_hex(digest_string b))
let digest s=String.length s=64&&String.for_all(function '0'..'9'|'a'..'f'->true|_->false)s
let profile="RECOVERY_REVIEWER_ISSUER_2KEY_PREPARATION_NOT_ADMITTED"
let purpose=function "reviewer"->"uos.sa-plan.recovery.review-evidence.v1"|"issuer"->"uos.sa-plan.recovery.issuer-evidence.v1"|_->failwith "role"
let request_keys=["schema";"profile";"request_id";"key_reference";"purpose";"header";"payload";"review_token";"configuration_sha256";"context_sha256";"native_request_sha256"]
let request_id j=sha(Yojson.Basic.to_string(`List(List.map(fun k->`String(text j k))["key_reference";"purpose";"header";"payload";"review_token";"configuration_sha256";"context_sha256";"native_request_sha256"])))
let payload_keys=["domain";"profile";"subject";"session";"actor";"configuration_sha256";"request_sha256";"context_sha256";"decision";"created_utc_ms";"expires_utc_ms";"created_mono_ms";"expires_mono_ms";"review_token_sha256"]
let sign body=
 need(String.length body<=32768);
 let j=Yojson.Basic.from_string body in closed j request_keys;
 need(Yojson.Basic.to_string j=body&&text j "schema"="uos.recovery.signing-request.v1"&&text j "profile"=profile);
 let role=match text j "key_reference"with "uos-recovery-reviewer-v1"->"reviewer"|"uos-recovery-issuer-v1"->"issuer"|_->failwith "fixed test reference"in
 need(text j "purpose"=purpose role&&text j "request_id"=request_id j);
 let h=Yojson.Basic.from_string(text j "header")and p=Yojson.Basic.from_string(text j "payload")in
 closed h ["alg";"kid";"typ"];closed p payload_keys;
 need(Yojson.Basic.to_string h=text j "header"&&Yojson.Basic.to_string p=text j "payload");
 need(text h "alg"="EdDSA"&&text h "kid"=role^"-key"&&text h "typ"="JWT");
 need(text p "domain"=purpose role&&text p "profile"=profile&&text p "decision"="attest_evidence_only");
 List.iter(fun field->need(text p field=role^"-"^field))["subject";"session";"actor"];
 List.iter(fun(outer,inner)->need(digest(text j outer)&&text j outer=text p inner))
  ["configuration_sha256","configuration_sha256";"context_sha256","context_sha256";"native_request_sha256","request_sha256"];
 let int k=Yojson.Basic.Util.(to_int(member k p))in
 let created=int "created_utc_ms"and expires=int "expires_utc_ms"and mono=int "created_mono_ms"and until=int "expires_mono_ms"in
 need(created>=0&&created<expires&&expires<=9223372036854&&expires-created<=600000
  &&mono>= -9000000000000000&&until<=9000000000000000&&mono<until&&until-mono<=600000);
 let review=text j "review_token"in
 need(String.length review<=8192&&if role="reviewer"then review=""&&text p "review_token_sha256"=""else review<>""&&text p "review_token_sha256"=sha review);
 if role="issuer"then(
  match String.split_on_char '.' review with
  |[h64;p64;signature]->
   let rh=unb64 h64 and rp=unb64 p64 in
   let header=Yojson.Basic.from_string rh and review_payload=Yojson.Basic.from_string rp in
   closed header["alg";"kid";"typ"];closed review_payload payload_keys;
   need(Yojson.Basic.to_string header=rh&&Yojson.Basic.to_string review_payload=rp
    &&text header"alg"="EdDSA"&&text header"kid"="reviewer-key"&&text header"typ"="JWT");
   need(Mirage_crypto_ec.Ed25519.verify~key:(Mirage_crypto_ec.Ed25519.pub_of_priv(key"reviewer"))(unb64 signature)~msg:(h64^"."^p64));
   need(text review_payload"domain"=purpose"reviewer"&&text review_payload"profile"=profile
    &&text review_payload"subject"="reviewer-subject"&&text review_payload"session"="reviewer-session"
    &&text review_payload"actor"="reviewer-actor"&&text review_payload"decision"="attest_evidence_only"
    &&text review_payload"review_token_sha256"="");
   List.iter(fun field->need(Yojson.Basic.Util.member field review_payload=Yojson.Basic.Util.member field p))
    ["configuration_sha256";"context_sha256";"request_sha256";"created_utc_ms";"expires_utc_ms";"created_mono_ms";"expires_mono_ms"]
  |_->failwith"linked reviewer signature required");
 let bytes=b64(text j "header")^"."^b64(text j "payload")in
 let token=bytes^"."^b64(Mirage_crypto_ec.Ed25519.sign ~key:(key role)bytes)in
 Yojson.Basic.to_string(`Assoc["schema",`String"uos.recovery.signing-response.v1";"request_id",`String(text j "request_id");"key_reference",`String(text j "key_reference");"token",`String token;"authority",`String"NONE";"admitted",`Bool false])
let ()=
 if Array.length Sys.argv=2&&Sys.argv.(1)="--public"then
  print_endline(Yojson.Basic.to_string(`Assoc["reviewer",`String(public "reviewer");"issuer",`String(public "issuer")]))
 else(
  let response=try
   need(Array.length Sys.argv=2);
   let ch=open_in_bin Sys.argv.(1)in
   let marker=Fun.protect ~finally:(fun()->close_in ch)(fun()->let n=in_channel_length ch in need(n=39);really_input_string ch n)in
   need(marker="PRIVATE_RECOVERY_SIGNER_FIXTURE_ONLY_V1");
   let h=really_input_string stdin 4 in let n=ref 0 in String.iter(fun c->n:=(!n lsl 8)lor Char.code c)h;
   need(!n>0&& !n<=32768);let body=really_input_string stdin !n in
   (try ignore(input_char stdin);failwith "trailing"with End_of_file->());sign body
   with _->"{\"status\":\"HOLD\",\"code\":\"FIXTURE_SIGNER_UNAVAILABLE\"}"in
  let n=String.length response in for i=3 downto 0 do output_char stdout(Char.chr((n lsr(8*i))land 255))done;
  output_string stdout response;flush stdout)
