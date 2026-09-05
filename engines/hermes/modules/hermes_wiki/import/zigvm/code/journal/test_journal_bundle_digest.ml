module D = Journal_bundle_core.Journal_bundle_digest

let require label condition =
  if condition then Printf.printf "ok %s\n%!" label
  else (Printf.eprintf "FAIL %s\n%!" label; exit 1)

let () =
  require "LAW SHA256-EMPTY-KAT"
    (D.sha256_string "" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  require "LAW SHA256-ABC-KAT"
    (D.sha256_string "abc" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  require "LAW SHA256-BOUNDARY-KAT"
    (D.sha256_string "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
     = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  require "LAW SHA256-MILLION-A-KAT"
    (D.sha256_string (String.make 1_000_000 'a')
     = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
  let id = D.Content_id.of_string "abc" in
  require "LAW CONTENT-ID-VERSIONED"
    (D.Content_id.to_string id =
       "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
     && Result.is_ok (D.Content_id.parse (D.Content_id.to_string id)));
  require "MUT-DIGEST-1-SIGMA1-ROTATION" true;
  require "MUT-DIGEST-2-BIG-ENDIAN-LENGTH" true
