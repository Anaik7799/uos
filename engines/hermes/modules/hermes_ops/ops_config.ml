(* Declarative configuration — see ops_config.mli for the laws. *)

type layer =
  | L0_product | L1_family | L2_capability | L3_contract | L4_fixture
  | L5_trace | LX_control

type supply = Environment | Toolchain | Derived
type secrecy = Not_secret | Presence_only | Value_used
type necessity = Required | Optional_flag | Override

type element = {
  key : string;
  layer : layer;
  supply : supply;
  secrecy : secrecy;
  necessity : necessity;
  purpose : string;
  consumer : string;
  note : string;
}

let layer_name = function
  | L0_product -> "L0 product"
  | L1_family -> "L1 family"
  | L2_capability -> "L2 capability"
  | L3_contract -> "L3 contract"
  | L4_fixture -> "L4 fixture"
  | L5_trace -> "L5 trace"
  | LX_control -> "LX control-plane"

let layers =
  [ L0_product; L1_family; L2_capability; L3_contract; L4_fixture; L5_trace; LX_control ]

let e ?(note = "") key layer supply secrecy necessity purpose consumer =
  { key; layer; supply; secrecy; necessity; purpose; consumer; note }

(* THE MODEL. Every configuration element the system has, declared once.
   Adding a `Sys.getenv` without adding a line here fails the gate. *)
let elements =
  [ e "OPENROUTER_API_KEY" L4_fixture Environment Presence_only Optional_flag
      "Presence flag for the local bootstrap configuration probe."
      "modules/hermes_harness/bootstrap.ml"
      ~note:
        "The probe evaluates `Option.is_some (Sys.getenv_opt ...)` and NEVER reads \
         the value, so no code path can leak it — and a syntactically valid but \
         DEAD key still yields a green bootstrap, because the probe reports \
         configuration, not reachability. Supplied for one command at a time from \
         the c3i environment file; never sourced, never exported into a shell.";
    e "QCHECK_SEED" L4_fixture Environment Not_secret Optional_flag
      "Pins the QCheck generator seed so a fuzz failure can be replayed exactly."
      "modules/hermes_harness/qcheck_seed.ml"
      ~note:
        "Absent => a fresh random seed, which is the normal mode. Present and \
         unparseable => a REFUSAL (exit 2), never a silent fallback: a run that \
         looks reproducible and is not would defeat the determinacy gate (R14) \
         this variable exists to serve. An explicit --seed on argv wins over it.";
    e "HERMES_Z3" L3_contract Environment Not_secret Override
      "SMT solver used to discharge the topology constraints."
      "(several, including modules/hermes_ops/ops_verify.ml)"
      ~note:"Absent => the Z3 leg is UNAVAILABLE, never DISCHARGED (R2).";
    e "HERMES_GOSPEL" L3_contract Environment Not_secret Override
      "Gospel contract checker for .mli specifications."
      "modules/hermes_harness/gospel_check.ml"
      ~note:
        "`ops formal` currently reports 12 Gospel artifacts UNAVAILABLE because the \
         checker cannot resolve sibling modules without load paths. That is an \
         invocation gap, not a specification defect.";
    e "HERMES_COQC" L3_contract Environment Not_secret Override
      "Coq/Rocq compiler for the parity-lattice proofs."
      "modules/hermes_harness/test_rocq_lattice.ml" ;
    e "HERMES_REFERENCE_PYTHON" L4_fixture Environment Not_secret Optional_flag
      "Interpreter for the FROZEN reference the candidate is compared against."
      "modules/hermes_harness/test_reference_capture.ml"
      ~note:
        "The reference is RUN, never reimplemented in OCaml — that is the parity \
         discipline. Provisioned under state/reference_env/, which is gitignored: \
         a tool for running the measured system, not part of the harness.";
    e "HERMES_ZENOH" L5_trace Environment Not_secret Optional_flag
      "Enables the Zenoh telemetry mesh leg." "modules/hermes_harness/test_hermes_zenoh.ml"
      ~note:"Unset => that suite discloses a skip rather than passing quietly.";
    e "HERMES_ZENOH_ENDPOINT" L5_trace Environment Not_secret Override
      "Endpoint the telemetry mesh binds or connects to."
      "modules/hermes_harness/test_hermes_zenoh.ml"
      ~note:"Meaningful only with HERMES_ZENOH set; alone it changes nothing.";
    e "ZELLIJ_SESSION_NAME" L5_trace Derived Presence_only Optional_flag
      "Presence identity reported by Zellij for the currently observed session."
      "modules/hermes_zellij/zellij_observe.ml"
      ~note:
        "Zellij supplies this value to its child process. Hermes observes presence \
         only; it never reads or persists the session name, and the generated \
         environment template must not ask an operator to configure it.";
    e "ZIGVM_ROOT" L1_family Environment Not_secret Override
      "Local checkout of the prior zigvm harness (R14 reuse)."
      "modules/hermes_wiki/import/zigvm/code/core/test_route_algebra.ml"
      ~note:"The tracked mirrors under modules/hermes_wiki/import/zigvm/ need none of these.";
    e "ZIGVM_WORK_ROOT" L1_family Environment Not_secret Override
      "Working root for imported zigvm planning code."
      "modules/hermes_wiki/import/zigvm/code/infranodus/infranodus_fractal_closure_plan.ml";
    e "ZIGVM_SA_PLAN_DB" L1_family Environment Not_secret Override
      "SQLite database backing the imported SA-plan."
      "modules/hermes_wiki/import/zigvm/code/infranodus/infranodus_fractal_closure_plan.ml";
    e "WIKI_AUDIT_DEBUG" LX_control Environment Not_secret Optional_flag
      "Verbose output from the wiki audit." "modules/hermes_wiki/src/tools/wiki_audit.ml"
      ~note:
        "Changes OUTPUT ONLY. No gauge, verdict or exit code moves — a debug flag \
         that altered a verdict would be a way to make a breach disappear.";
    e "PATH" L0_product Toolchain Not_secret Required
      "Locates every external oracle; established by the opam switch."
      "(several)"
      ~note:
        "Established by `eval $(opam env --switch=/home/an/dev/ver/zigvm --set-switch)`, \
         not by this file. The declared switch is NOT the one a shell defaults to.";
    e "HOME" L0_product Derived Not_secret Required
      "Resolves user-scoped paths." "(several)";
    e "PWD" L0_product Derived Not_secret Required
      "Repo-root-relative measurement; R19 clause 5." "(several)"
      ~note:
        "Every operator tool measures from the repo root. A drifted cwd once cost \
         several minutes chasing phantom failures.";
    e "PYTHONPATH" L4_fixture Environment Not_secret Override
      "Import path for the frozen reference adapter."
      "modules/hermes_harness/reference_adapter" ;
    e "HERMES_VISION_VM1" L4_fixture Environment Not_secret Override
      "AI Processing for VM-1 Satellite" "projects/satellites/vision/vm1_processor.ml" ;
    e "HERMES_VISION_UI_PORT" LX_control Environment Not_secret Override
      "Dashboard Port for Dream Server" "modules/hermes_vision/vision_server.ml" ;
    e "HERMES_VISION_KPI_WS" LX_control Environment Not_secret Override
      "KPI Websocket for Bonsai UI" "modules/hermes_wiki/src/frontend/vision_ui.ml" ;
    e "HERMES_DATARHEI_WEBRTC" L4_fixture Environment Not_secret Override
      "Local Transmuxer Sink Address" "modules/hermes_vision/vision_server.ml" ;
    e "HERMES_OVENPLAYER_STATIC" LX_control Environment Not_secret Override
      "Zero-dependency isolated JS artifact" "modules/hermes_vision/vision_server.ml";
    e "DREAM_PORT" LX_control Environment Not_secret Override
      "Bounded TCP port for the read-only agentic model and Swarm dashboard."
      "modules/swarm/lmstudio_dashboard_web.ml"
      ~note:
        "Required at the operator boundary; absent, invalid, or out of range is \
         a refusal. The declared operational value is 9501.";
    e "HERMES_TAILSCALE_FQDN" L5_trace Environment Not_secret Override
      "Tailscale DNS name used to generate the dashboard's only public URL."
      "modules/swarm/run_lmstudio_dashboard.ml"
      ~note:
        "Required; no hard-coded or local fallback exists. The rendered snapshot \
         validator accepts only HTTP(S) hosts ending in .ts.net and rejects \
         localhost, wildcard binds, userinfo, and raw IPs.";
    e "JUJUTSU_RELEASE_ID" LX_control Derived Not_secret Required
      "Identity of the exact frozen Jujutsu release contract."
      "modules/hermes_vcs/jj_release_authority.ml";
    e "JUJUTSU_CONFIG_ID" LX_control Derived Not_secret Required
      "Identity of the isolated Jujutsu configuration contract."
      "modules/hermes_vcs/jj_source_authority.ml";
    e "JUJUTSU_OPERATOR_PUBLIC_KEY_ID" LX_control Derived Not_secret Required
      "Opaque identity of the configured operator public key, never key material."
      "modules/hermes_ops/dependability_approval.ml";
    e "JUJUTSU_RESOURCE_BUDGET_PROFILE" LX_control Derived Not_secret Required
      "Identity of the bounded resource and output budget profile."
      "modules/hermes_ops/run_jj_authority.ml";
    e "JUJUTSU_SOURCE_CARRIER_POLICY" LX_control Derived Not_secret Required
      "Identity of the source-only carrier and exclusion policy."
      "modules/hermes_vcs/mainline_carrier_policy.ml";
    e "JUJUTSU_APPROVAL_POLICY" LX_control Derived Not_secret Required
      "Identity of the campaign approval and nonce policy."
      "modules/hermes_ops/dependability_approval.ml";
    e "JUJUTSU_WRITER_LEASE_POLICY" LX_control Derived Not_secret Required
      "Identity of the writer lease, fence, and expiry policy."
      "modules/hermes_ops/dependability_writer_lease.ml";
    e "JUJUTSU_CREDENTIAL_POLICY" LX_control Derived Not_secret Required
      "Identity of the credential custody and redaction policy."
      "modules/hermes_ops/ops_credential_lease_target.ml";
    e "JUJUTSU_COMPLETION_RECONCILE_ATTEMPT_LIMIT" LX_control Derived Not_secret Required
      "Identity of the finite completion reconciliation attempt-bound policy."
      "modules/hermes_ops/dependability_authority_store.ml" ]

(* -------------------------------------------------------- projections *)

let necessity_word = function
  | Required -> "REQUIRED"
  | Optional_flag -> "optional (absent => disclosed skip, never a failure)"
  | Override -> "override (absent => default)"

let secrecy_word = function
  | Not_secret -> ""
  | Presence_only -> "  SECRET — presence only, the value is never read"
  | Value_used -> "  SECRET — the value IS consumed"

let env_template () =
  let b = Buffer.create 8192 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  p "# GENERATED by `ops config --template`. Do not edit.\n\
     #\n\
     # Configuration in this repository is DECLARATIVE INTENT: every element is\n\
     # declared once in modules/hermes_ops/ops_config.ml, with its fractal layer,\n\
     # its purpose and the file that reads it. This template is derived from that\n\
     # model, so it cannot drift from it — and `ops config --check` fails the\n\
     # build if any code reads a variable the model does not declare.\n\
     #\n\
     # Edit the model, regenerate. Never edit this file.\n\
     #\n\
     # NO VALUES HERE, ever. Copy to `.env` (already gitignored) and fill that.\n\
     #\n\
     # The toolchain comes first and is NOT set by this file:\n\
     #   eval $(opam env --switch=/home/an/dev/ver/zigvm --set-switch)\n\
     #   dune exec modules/hermes_toolchain/toolchain_check.exe\n";
  List.iter
    (fun l ->
      let mine = List.filter (fun x -> x.layer = l && x.supply = Environment) elements in
      if mine <> [] then begin
        p "\n# %s\n# %s\n" (String.make 74 '=') (layer_name l);
        p "# %s\n" (String.make 74 '=');
        List.iter
          (fun x ->
            p "\n# %s\n" x.purpose;
            p "# read by: %s\n" x.consumer;
            p "# %s%s\n" (necessity_word x.necessity) (secrecy_word x.secrecy);
            if x.note <> "" then begin
              (* wrap the note at ~72 columns so the file stays readable *)
              let words = String.split_on_char ' ' x.note in
              let line = Buffer.create 80 in
              List.iter
                (fun w ->
                  if Buffer.length line + String.length w > 70 then begin
                    p "# %s\n" (Buffer.contents line);
                    Buffer.clear line
                  end;
                  if Buffer.length line > 0 then Buffer.add_char line ' ';
                  Buffer.add_string line w)
                words;
              if Buffer.length line > 0 then p "# %s\n" (Buffer.contents line)
            end;
            p "%s=\n" x.key)
          mine
      end)
    layers;
  Buffer.contents b

let render () =
  let b = Buffer.create 4096 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  List.iter
    (fun l ->
      let mine = List.filter (fun x -> x.layer = l) elements in
      if mine <> [] then begin
        p "\n%s\n" (layer_name l);
        List.iter
          (fun x ->
            p "  %-26s %-9s %s\n" x.key
              (match x.supply with
              | Environment -> "env"
              | Toolchain -> "toolchain"
              | Derived -> "derived")
              x.purpose)
          mine
      end)
    layers;
  Buffer.contents b

let schema_id = "hermes.ops-config/v2"

let layer_key = function
  | L0_product -> "l0-product" | L1_family -> "l1-family"
  | L2_capability -> "l2-capability" | L3_contract -> "l3-contract"
  | L4_fixture -> "l4-fixture" | L5_trace -> "l5-trace"
  | LX_control -> "lx-control"

let supply_key = function
  | Environment -> "environment" | Toolchain -> "toolchain"
  | Derived -> "derived"

let secrecy_key = function
  | Not_secret -> "not-secret" | Presence_only -> "presence-only"
  | Value_used -> "value-used"

let necessity_key = function
  | Required -> "required" | Optional_flag -> "optional-flag"
  | Override -> "override"

let length_frame values =
  values
  |> List.map (fun value -> string_of_int (String.length value) ^ ":" ^ value)
  |> String.concat ""

let declaration_digest_of declarations =
  schema_id
  :: List.concat_map
       (fun item ->
         [ item.key; layer_key item.layer; supply_key item.supply;
           secrecy_key item.secrecy; necessity_key item.necessity;
           item.purpose; item.consumer; item.note ])
       (List.sort
          (fun left right -> String.compare left.key right.key)
          declarations)
  |> length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let declaration_digest = declaration_digest_of elements
