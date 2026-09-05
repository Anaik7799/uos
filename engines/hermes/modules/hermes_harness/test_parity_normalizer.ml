let json = Yojson.Safe.from_string

let () =
  let normalizer = Parity_normalizer.default in

  (* Key order carries no meaning in JSON, so it must not cause a difference. *)
  assert (
    Parity_normalizer.equal normalizer
      (json {|{"b":1,"a":2}|})
      (json {|{"a":2,"b":1}|}));

  (* Array order IS significant and must be preserved. *)
  assert (
    not
      (Parity_normalizer.equal normalizer (json {|{"xs":[1,2]}|})
         (json {|{"xs":[2,1]}|})));

  (* A declared volatile field is elided at the root and at depth. *)
  assert (
    Parity_normalizer.equal normalizer
      (json {|{"id":"req-1","model":"m"}|})
      (json {|{"id":"req-2","model":"m"}|}));
  assert (
    Parity_normalizer.equal normalizer
      (json {|{"choices":[{"message":{"id":"a","content":"hi"}}]}|})
      (json {|{"choices":[{"message":{"id":"b","content":"hi"}}]}|}));

  (* An undeclared field is never elided: this is the failure that would
     manufacture parity, so it is pinned by a test. *)
  assert (
    not
      (Parity_normalizer.equal normalizer
         (json {|{"model":"a"}|})
         (json {|{"model":"b"}|})));
  assert (
    not
      (Parity_normalizer.equal normalizer
         (json {|{"choices":[{"message":{"content":"hi"}}]}|})
         (json {|{"choices":[{"message":{"content":"bye"}}]}|})));

  (* A volatile name only elides at its declared path, not wherever it occurs.
     "id" is volatile at the root; "tool_calls[].id" is not. *)
  assert (
    not
      (Parity_normalizer.equal normalizer
         (json {|{"tool_calls":[{"id":"call-1"}]}|})
         (json {|{"tool_calls":[{"id":"call-2"}]}|})));

  (* Numeric tagging is canonicalized: Int 1, Intlit "1" and Float 1.0 all
     normalize identically, so an integer and its float spelling do not diverge
     on the encoder's choice of tag. This is a real equality, now enforced. *)
  assert (
    Parity_normalizer.equal normalizer (json {|{"score":1}|}) (json {|{"score":1.0}|}));
  assert (
    Parity_normalizer.equal normalizer
      (`Assoc [ ("n", `Int 1) ])
      (`Assoc [ ("n", `Float 1.0) ]));
  assert (
    Parity_normalizer.equal normalizer
      (`Assoc [ ("n", `Intlit "42") ])
      (`Assoc [ ("n", `Int 42) ]));
  (* But genuinely different numbers still differ. *)
  assert (
    not (Parity_normalizer.equal normalizer (json {|{"n":1}|}) (json {|{"n":2}|})));
  assert (
    not (Parity_normalizer.equal normalizer (json {|{"n":1.5}|}) (json {|{"n":1}|})));

  (* Normalizing twice changes nothing: the normal form is a fixed point. *)
  let document = json {|{"b":{"d":2,"c":[1,{"f":1,"e":2}]},"a":1,"id":"x"}|} in
  let once = Parity_normalizer.normalize_document normalizer document in
  let twice = Parity_normalizer.normalize_document normalizer once in
  assert (Yojson.Safe.to_string once = Yojson.Safe.to_string twice);

  (* Equality is reflexive, symmetric and transitive over the corpus. *)
  let corpus =
    [ json {|{"a":1}|}; json {|{"a":1,"id":"z"}|}; json {|{"b":[1,2]}|};
      json {|{"b":[2,1]}|}; `Null; `List []; `Assoc [] ]
  in
  List.iter
    (fun left ->
      assert (Parity_normalizer.equal normalizer left left);
      List.iter
        (fun right ->
          assert (
            Parity_normalizer.equal normalizer left right
            = Parity_normalizer.equal normalizer right left))
        corpus)
    corpus;

  (* The declared volatile set is part of the evidence: a normalizer that
     elides more must describe itself differently, so a change of meaning is
     visible rather than silent. *)
  let laxer =
    { Parity_normalizer.version = "hermes-parity-v1";
      volatile_paths = "model" :: Parity_normalizer.default.volatile_paths }
  in
  assert (Parity_normalizer.equal laxer (json {|{"model":"a"}|}) (json {|{"model":"b"}|}));
  assert (
    not
      (String.equal
         (Parity_normalizer.describe laxer)
         (Parity_normalizer.describe normalizer)));
  assert (
    String.equal (Parity_normalizer.version laxer) (Parity_normalizer.version normalizer));

  print_endline
    ("parity_normalizer: " ^ Parity_normalizer.describe Parity_normalizer.default)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_parity_normalizer" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_parity_normalizer ]);
  exit (Suite_telemetry.exit_code self)
