(* The toolchain gate's PURE core. It is a library, not a copy pasted
   into a test: the first cut duplicated these functions by value into
   `test_toolchain_check.ml` with a comment claiming a divergence would
   be "caught by T5, which runs the real tool". T5 did not run the real
   tool, and the two copies HAD already diverged (one handled tabs, one
   did not). A library adds no switch dependency — the reason given for
   the copy did not hold — and it is the only way a test can be evidence
   about the thing that ships. *)

(* ---------------------------------------------------------- dune text *)

(* `;` runs to end of line in dune. Unhandled, a comment inside a
   `(libraries …)` stanza turned every English word into a required opam
   package and REFUSED a perfectly good switch; a commented-out stanza
   was counted as real. Both directions were live risks in a tree whose
   dune files are heavily commented. *)
let strip_comments text =
  String.split_on_char '\n' text
  |> List.map (fun line ->
         match String.index_opt line ';' with
         | Some i -> String.sub line 0 i
         | None -> line)
  |> String.concat "\n"

let tokens_of s =
  s
  |> String.split_on_char ' '
  |> List.concat_map (String.split_on_char '\n')
  |> List.concat_map (String.split_on_char '\t')
  |> List.concat_map (String.split_on_char '\r')
  |> List.filter (fun t -> t <> "")

(* The body of every stanza opened by [key], paren-balanced. Tokens
   nested deeper than the stanza itself are returned too when [deep] is
   set: `(re_export tyxml)` MEANS tyxml is a dependency, and dropping it
   was a missed dependency the first cut's own test had ratified. *)
let stanza_bodies ~key ~deep text =
  let text = strip_comments text in
  let n = String.length text in
  let nk = String.length key in
  let out = ref [] in
  let i = ref 0 in
  while !i + nk <= n do
    if String.sub text !i nk = key then begin
      let j = ref (!i + nk) in
      let buf = Buffer.create 64 in
      let depth = ref 1 in
      while !j < n && !depth > 0 do
        (match text.[!j] with
        | '(' ->
            incr depth;
            if deep then Buffer.add_char buf ' '
        | ')' ->
            decr depth;
            if deep && !depth > 0 then Buffer.add_char buf ' '
        | c -> if deep || !depth = 1 then Buffer.add_char buf c);
        incr j
      done;
      out := Buffer.contents buf :: !out;
      i := !j
    end
    else incr i
  done;
  List.rev !out

(* Dune keywords that appear INSIDE a libraries stanza and are not
   packages: `(re_export x)` and `(select … from …)`. *)
let stanza_keywords = [ "re_export"; "select"; "from"; "->" ]

let libraries_of_dune text =
  stanza_bodies ~key:"(libraries" ~deep:true text
  |> List.concat_map tokens_of
  |> List.filter (fun t -> not (List.mem t stanza_keywords))
  (* `(select foo.ml from …)` names FILES, not packages *)
  |> List.filter (fun t -> not (Filename.check_suffix t ".ml"))
  |> List.sort_uniq compare

(* PPX packages are real opam dependencies and live in `(preprocess (pps
   …))`, not in `(libraries …)`. The first cut missed the entire class —
   including `ppx_jane`, which its own comment used as the worked
   example. A switch missing ppx_jane passed the gate and then failed the
   build. *)
let pps_of_dune text =
  stanza_bodies ~key:"(pps" ~deep:true text
  |> List.concat_map tokens_of
  |> List.filter (fun t -> not (List.mem t stanza_keywords))
  |> List.sort_uniq compare

(* Names this tree DEFINES. `(name x)`, `(names a b c)` and
   `(public_name p)` all bind. Matching the bare prefix `"(name"` used to
   capture `(names hde_stubs)` as the single junk token "s hde_stubs" and
   to miss every public name. *)
let defined_in_dune text =
  let text = strip_comments text in
  let of_key key =
    stanza_bodies ~key ~deep:false text |> List.concat_map tokens_of
  in
  of_key "(name " @ of_key "(names " @ of_key "(public_name "
  |> List.map (fun n ->
         (* a public name is `package.lib`; both halves shadow *)
         match String.index_opt n '.' with
         | Some i -> [ n; String.sub n 0 i ]
         | None -> [ n ])
  |> List.concat |> List.sort_uniq compare

let stdlib_provided =
  [ "unix"; "str"; "threads"; "threads.posix"; "dynlink"; "bigarray"; "compiler-libs";
    "compiler-libs.common"; "runtime_events" ]

let package_of lib = match String.index_opt lib '.' with Some i -> String.sub lib 0 i | None -> lib

let external_libraries ~used ~defined =
  used
  |> List.filter (fun l ->
         (not (List.mem l defined))
         && (not (List.mem (package_of l) defined))
         && not (List.mem l stdlib_provided))
  |> List.map package_of
  |> List.sort_uniq compare

(* ------------------------------------------------ approval crypto provenance *)

type approval_crypto_refusal =
  | Approval_crypto_dependency_not_derived
  | Approval_crypto_version_unavailable
  | Approval_crypto_version_mismatch of {
      expected : string;
      observed : string;
    }
  | Approval_crypto_manifest_missing
  | Approval_crypto_manifest_mismatch
  | Approval_crypto_self_test_unavailable
  | Approval_crypto_self_test_failed

let approval_crypto_package = "mirage-crypto-ec"
let approval_crypto_version = "2.2.0"

(* The manifest is an immutable source-provenance record.  Byte equality is
   intentional: accepting a reordered, extended, or otherwise reinterpreted
   record would make the gate depend on an unversioned parser policy. *)
let approval_crypto_manifest =
  "(\n\
  \  (package \"mirage-crypto-ec\")\n\
  \  (version \"2.2.0\")\n\
  \  (source-url \"https://github.com/mirage/mirage-crypto/releases/download/v2.2.0/mirage-crypto-2.2.0.tbz\")\n\
  \  (source-commit \"5f26ca1c9284fe9c93ab23768ff88ba345b360c5\")\n\
  \  (archive-sha256 \"4b87091b6a77843bf97a74aae2e7da21310307ff7d2105712c4369680122d80a\")\n\
  \  (archive-sha512 \"3361649703d0e391e5adc40770dcb4dcbee2ecd27a64962e28c7f8240a67131efe9226a5240ac7a019c1464f217abec9c71dbb8412ef2b4eafeb4ad8e3931805\")\n\
  \  (api \"Mirage_crypto_ec.Ed25519.verify ~key signature ~msg\")\n\
  )\n"

let validate_approval_crypto_supply_chain ~derived_packages
    ~installed_version ~provenance_manifest ~provider_self_test =
  let refusals = ref [] in
  let refuse reason = refusals := reason :: !refusals in
  if not (List.mem approval_crypto_package derived_packages) then
    refuse Approval_crypto_dependency_not_derived;
  begin
    match installed_version with
    | None | Some "" -> refuse Approval_crypto_version_unavailable
    | Some observed when observed <> approval_crypto_version ->
        refuse
          (Approval_crypto_version_mismatch
             { expected = approval_crypto_version; observed })
    | Some _ -> ()
  end;
  begin
    match provenance_manifest with
    | None -> refuse Approval_crypto_manifest_missing
    | Some observed when observed <> approval_crypto_manifest ->
        refuse Approval_crypto_manifest_mismatch
    | Some _ -> ()
  end;
  begin
    match provider_self_test with
    | None -> refuse Approval_crypto_self_test_unavailable
    | Some false -> refuse Approval_crypto_self_test_failed
    | Some true -> ()
  end;
  match List.rev !refusals with [] -> Ok () | errors -> Error errors

let string_of_approval_crypto_refusal = function
  | Approval_crypto_dependency_not_derived ->
      "mirage-crypto-ec was not derived from the live Dune library denominator"
  | Approval_crypto_version_unavailable ->
      "the installed mirage-crypto-ec version is unavailable"
  | Approval_crypto_version_mismatch { expected; observed } ->
      Printf.sprintf "installed mirage-crypto-ec version is %s, expected %s"
        observed expected
  | Approval_crypto_manifest_missing ->
      "the frozen mirage-crypto-ec release-provenance manifest is missing"
  | Approval_crypto_manifest_mismatch ->
      "the frozen mirage-crypto-ec release-provenance manifest is mutated"
  | Approval_crypto_self_test_unavailable ->
      "the Ed25519 verification-only provider self-test is unavailable"
  | Approval_crypto_self_test_failed ->
      "the Ed25519 verification-only provider self-test failed"
