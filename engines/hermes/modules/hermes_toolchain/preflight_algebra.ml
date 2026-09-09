(* Denotational semantics for the UOS toolchain preflight (SC-NIX-DEVENV-001).
   Pure: no filesystem, process, network or clock. See the .mli for the domain. *)

type finding = { arm : string; name : string; detail : string }

type verdict = Pass | Fail of finding list

let top = Pass

(* Meet. Pass is the identity, Fail absorbs, and findings CONCATENATE so a
   composite failure names every failing arm rather than the first one. *)
let meet a b =
  match (a, b) with
  | Pass, Pass -> Pass
  | Pass, Fail f | Fail f, Pass -> Fail f
  | Fail f, Fail g -> Fail (f @ g)

let meet_all vs = List.fold_left meet top vs

let is_pass = function Pass -> true | Fail _ -> false
let findings = function Pass -> [] | Fail f -> f

let fail arm name detail = Fail [ { arm; name; detail } ]

type execution =
  | Not_executable
  | Exited_nonzero of int
  | Exited_zero_silent
  | Exited_zero_with_output of string

type probe_expectation = Silent_ok | Output_required

(* Total interpretation: every observation denotes a verdict, and everything
   that is not positive evidence of working denotes Fail. There is deliberately
   no Unknown constructor -- an unrepresentable third state cannot be silently
   treated as success. *)
let interpret_execution ~arm ~name expectation obs =
  match (obs, expectation) with
  | Exited_zero_with_output _, _ -> Pass
  | Exited_zero_silent, Silent_ok -> Pass
  | Exited_zero_silent, Output_required ->
      fail arm name "exit 0 but produced NO output (empty executable?)"
  | Exited_nonzero c, _ -> fail arm name ("exit " ^ string_of_int c)
  | Not_executable, _ -> fail arm name "not executable"

let has_prefix ~prefix s =
  let n = String.length prefix in
  String.length s >= n && String.sub s 0 n = prefix

let interpret_locality ~name ~root ~entrypoint ~resolved ~barred_prefixes =
  (* The entrypoint must be ours. Where it RESOLVES to may be /nix/store -- the
     honest boundary -- but must not be a $HOME, host or evidence-tree path. *)
  let entry_v =
    if has_prefix ~prefix:(root ^ "/") entrypoint then Pass
    else fail "locality" name ("entrypoint escapes the project root: " ^ entrypoint)
  in
  let resolved_v =
    match List.find_opt (fun p -> has_prefix ~prefix:p resolved) barred_prefixes with
    | Some p -> fail "locality" name ("resolves into a barred tree " ^ p ^ ": " ^ resolved)
    | None -> Pass
  in
  meet entry_v resolved_v

let interpret_tracking ~tracked ~present =
  let module S = Set.Make (String) in
  let t = S.of_list tracked and p = S.of_list present in
  let untracked = S.diff p t and phantom = S.diff t p in
  let v1 =
    if S.is_empty untracked then Pass
    else
      Fail
        (S.elements untracked
        |> List.map (fun f -> { arm = "tracked"; name = f; detail = "present but not tracked" }))
  in
  let v2 =
    if S.is_empty phantom then Pass
    else
      Fail
        (S.elements phantom
        |> List.map (fun f -> { arm = "tracked"; name = f; detail = "tracked but absent on disk" }))
  in
  meet v1 v2

type receipt = {
  status : verdict;
  epoch_s : int;
  checker_sha256 : string;
  table_sha256 : string;
}

(* Four independent conditions, conjoined by the same meet. A cached PASS is
   evidence about a specific checker reading a specific table; drop either
   digest and the receipt would lend its confidence to code it never saw. *)
let receipt_valid ~now_s ~max_age_s ~checker_sha256 ~table_sha256 r =
  let status_v =
    if is_pass r.status then Pass
    else fail "receipt" "status" "cached verdict is FAIL"
  in
  let age = now_s - r.epoch_s in
  let age_v =
    if age >= 0 && age <= max_age_s then Pass
    else
      fail "receipt" "age"
        ("receipt stale: age " ^ string_of_int age ^ "s > " ^ string_of_int max_age_s ^ "s")
  in
  let checker_v =
    if r.checker_sha256 = checker_sha256 then Pass
    else fail "receipt" "checker" "checker changed since the receipt was written"
  in
  let table_v =
    if r.table_sha256 = table_sha256 then Pass
    else fail "receipt" "table" "resolver table changed since the receipt was written"
  in
  meet_all [ status_v; age_v; checker_v; table_v ]

module Laws = struct
  let meet_associative a b c = meet (meet a b) c = meet a (meet b c)
  let meet_commutative a b = is_pass (meet a b) = is_pass (meet b a)
  let meet_idempotent a = meet a a |> is_pass = is_pass a
  let meet_identity a = meet a top = a && meet top a = a

  let fail_absorbs a fs =
    let f = Fail fs in
    (not (is_pass (meet a f))) && not (is_pass (meet f a))

  let meet_all_pass_iff_all_pass vs = is_pass (meet_all vs) = List.for_all is_pass vs

  let findings_preserved vs =
    let composite = findings (meet_all vs) in
    List.for_all
      (fun v -> List.for_all (fun f -> List.mem f composite) (findings v))
      vs

  let silent_zero_is_not_success ~arm ~name =
    (not (is_pass (interpret_execution ~arm ~name Output_required Exited_zero_silent)))
    && is_pass (interpret_execution ~arm ~name Silent_ok Exited_zero_silent)

  let receipt_validity_antitone_in_age r max_age a b =
    (* a <= b: if invalid at the younger age it is invalid at the older one. *)
    if a > b then true
    else
      let v_a = receipt_valid ~now_s:(r.epoch_s + a) ~max_age_s:max_age
          ~checker_sha256:r.checker_sha256 ~table_sha256:r.table_sha256 r in
      let v_b = receipt_valid ~now_s:(r.epoch_s + b) ~max_age_s:max_age
          ~checker_sha256:r.checker_sha256 ~table_sha256:r.table_sha256 r in
      if is_pass v_a then true else not (is_pass v_b)

  let digest_change_invalidates r max_age =
    let other = r.checker_sha256 ^ "-changed" in
    (not
       (is_pass
          (receipt_valid ~now_s:r.epoch_s ~max_age_s:max_age ~checker_sha256:other
             ~table_sha256:r.table_sha256 r)))
    && not
         (is_pass
            (receipt_valid ~now_s:r.epoch_s ~max_age_s:max_age
               ~checker_sha256:r.checker_sha256 ~table_sha256:other r))
end
