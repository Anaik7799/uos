let guide_path = "docs/hermes/systematic-debugging.md"
let sop_path = "docs/hermes/sops/systematic-debugging.md"
let ontology_path = "docs/hermes/wiki/systematic-debugging-ontology.md"
let atlas_path = "docs/hermes/wiki/systematic-debugging-fractal-atlas.md"
let algebra_path = "docs/hermes/wiki/systematic-debugging-fractal-algebra.md"

let frontmatter ~id ~title ~ktype ~topics ~links =
  Printf.sprintf
    "---\nid: hermes-%s\ntitle: %s\naliases: [%s]\nstatus: published\ntype: reference\nktype: %s\nmaturity: evergreen\ndomain: hermes\ntopics: [%s]\nlinks: [%s]\ncreated: 2026-08-13\n---\n\n"
    id title id ktype (String.concat ", " topics) (String.concat ", " links)

let notice =
  "> GENERATED from `Debug_intent.all` and its typed kernel. Do not hand-edit; regenerate with `ops debugging --write-docs`.\n\n"

let escape value =
  value |> String.split_on_char '|' |> String.concat "\\|"
  |> String.split_on_char '\n' |> String.concat " "

let coordinate item =
  Ops_capability.string_of_level item.Ops_capability.level
  ^ "/" ^ Ops_capability.string_of_phase item.phase

let list_or_none values =
  if values = [] then "none" else String.concat ", " values

let effect_text = function
  | Debug_intent.Pure_diagnosis -> "pure diagnosis"
  | Corrective_via_bridge activity ->
      "correction via Run_swarm_bridge/" ^ activity

let render_ontology () =
  let buffer = Buffer.create 32768 in
  let add format = Printf.ksprintf (Buffer.add_string buffer) format in
  Buffer.add_string buffer
    (frontmatter ~id:"systematic-debugging-ontology"
       ~title:"Hermes systematic debugging ontology" ~ktype:"source"
       ~topics:[ "systematic-debugging"; "rca"; "ontology"; "dependability" ]
       ~links:[ "hermes-systematic-debugging-fractal-atlas";
                "hermes-systematic-debugging-fractal-algebra";
                "hermes-systematic-debugging" ]);
  Buffer.add_string buffer "# Hermes systematic debugging ontology\n\n";
  Buffer.add_string buffer notice;
  add "Authority: `Debug_intent.all` (`%s`). Denominator: **%d failure-family intents**.\n\n"
    Debug_intent.source_digest (List.length Debug_intent.all);
  Buffer.add_string buffer
    "## Typed carriers\n\n| Carrier | Meaning | Refusal boundary |\n|---|---|---|\n| `Debug_intent.t` | Closed declarative objective, symptoms, bounds, hypotheses, FPP map, and effect posture. | Unknown or malformed registry identity. |\n| `Debug_ontology.observation` | Evidence with fractal coordinate, RCA origin, freshness, time, and digest. | Empty, duplicate, stale, unavailable, or indeterminate evidence. |\n| `Debug_ontology.hypothesis` | Competing causal explanation and observable predictions. | Vacuous statement, missing predictions, or collapsed hypothesis set. |\n| `Debug_ontology.discriminator` | Bounded next measurement able to separate hypotheses. | No covered hypotheses, no measurement, or unbounded cost. |\n| `Debug_dependability.t` | Reproduction, signature, deterministic seed, resource bounds, controls, mutants, concurrency checks, and verification cone. | Any empty, zero, excessive, or missing dependable-test obligation. |\n| `Debug_protocol` phase | Opaque capability proving progress through declare, observe, orient, hypothesize, discriminate, correct, verify, close. | A phase cannot be constructed by skipping its predecessor. |\n| `Debug_protocol.receipt` | Closed evidence digest, root-cause identity, origin, and terminal stage. | Stale verification, empty root cause, or missing evidence. |\n\n";
  Buffer.add_string buffer
    "## Fractal coordinates and RCA origins\n\nEvery diagnostic carries one `L0..L6` coordinate and one canonical `Specification | Implementation | Environment | Evidence | Control` origin. A failure may block evidence collection at any origin; only an **established Implementation origin** may deny parity credit. Unavailable evidence remains `Unavailable_observed`, never success.\n\n";
  Buffer.add_string buffer
    "## State path\n\n`Declared → Observed → Oriented → Hypothesized → Discriminated → Corrected → Verified → Closed`. `Blocked` is a disclosed terminal observation, not a green receipt. Correction is never a direct debugging side effect: it requires a separately admitted `Run_swarm_bridge` activity.\n";
  Buffer.contents buffer

let render_atlas () =
  let buffer = Buffer.create 65536 in
  let add format = Printf.ksprintf (Buffer.add_string buffer) format in
  Buffer.add_string buffer
    (frontmatter ~id:"systematic-debugging-fractal-atlas"
       ~title:"Hermes systematic debugging fractal functional atlas"
       ~ktype:"source"
       ~topics:[ "systematic-debugging"; "fractal-functional-atlas"; "fpp"; "ops" ]
       ~links:[ "hermes-systematic-debugging-ontology";
                "hermes-systematic-debugging-fractal-algebra";
                "hermes-systematic-debugging" ]);
  Buffer.add_string buffer "# Hermes systematic debugging fractal functional atlas\n\n";
  Buffer.add_string buffer notice;
  Buffer.add_string buffer
    "The same pure diagnostic function recurs from programme to assertion: declare intent, observe fresh evidence, orient by coordinate and origin, retain competing hypotheses, choose the cheapest discriminating measurement, correct only through admitted authority, then verify the original and its dependency cone.\n\n";
  Buffer.add_string buffer
    "| Intent | Failure family | Module | Path | Symptoms | Next discriminator | Dependability bounds | FPP owner/component/channel | Effect | Status |\n|---|---|---|---|---|---|---|---|---|---|\n";
  List.iter
    (fun (item : Debug_intent.t) ->
      let bounds = item.dependability.bounds in
      add "| `%s` | `%s` | `%s` | %s | %s | %s | %dms/%LdB/%d attempts; %d controls; %d mutants | `%s/%s/%s` | %s | Implemented and typed; live diagnosis requires supplied evidence |\n"
        item.stable_id item.failure_family item.target_module_id
        (escape (String.concat " → " (List.map coordinate item.path)))
        (escape (list_or_none item.symptom_patterns))
        (escape item.next_measurement.measurement)
        bounds.timeout_ms bounds.maximum_memory_bytes bounds.maximum_attempts
        (List.length item.dependability.required_controls)
        (List.length item.dependability.mutation_targets)
        item.fpp.owner item.fpp.component item.fpp.channel
        (escape (effect_text item.effect_policy)))
    Debug_intent.all;
  Buffer.add_string buffer
    "\n## Cross-surface projection\n\nEach row is available as CLI `completion debug`, MCP `tools/call`, Zenoh command query, metrics/inventory, FPP component-channel-command-event-parameter carriers, and generated wiki/SOP projections. All surfaces return the same `Ops_command.receipt` algebra.\n";
  Buffer.contents buffer

let render_algebra () =
  let buffer = Buffer.create 24576 in
  Buffer.add_string buffer
    (frontmatter ~id:"systematic-debugging-fractal-algebra"
       ~title:"Hermes systematic debugging fractal functional algebra"
       ~ktype:"source"
       ~topics:[ "systematic-debugging"; "fractal-functional-algebra"; "rca"; "formal" ]
       ~links:[ "hermes-systematic-debugging-ontology";
                "hermes-systematic-debugging-fractal-atlas";
                "hermes-systematic-debugging" ]);
  Buffer.add_string buffer "# Hermes systematic debugging fractal functional algebra\n\n";
  Buffer.add_string buffer notice;
  Buffer.add_string buffer
    "## Operators\n\n- Evidence union `E₁ ⊔ E₂` is canonical, commutative, associative, and idempotent by observation identity.\n- Hypothesis elimination `H \\ X` is monotone: evidence may remove candidates but cannot silently invent a cause.\n- Verdict join is conservative: unavailable/stale/contradicted dominate optimistic states; closure is granted only by the typed protocol.\n- Failure effect is `Denies_credit` exactly for established `Implementation`; every other origin is `Blocks_credit`.\n- Fractal composition applies the same operators at programme, module, capability, activity, action, scenario, and assertion scales.\n\n## Laws and mechanical witnesses\n\n| Law | Positive witness | Negative control |\n|---|---|---|\n| Registry totality | Nine unique, valid intents and a SHA-256 authority digest. | Drop or duplicate an intent. |\n| Observation integrity | Fresh, digested, uniquely identified evidence advances the phase. | Empty, stale, unavailable, or duplicate observation. |\n| Hypothesis plurality | At least two predictive alternatives enter discrimination. | Vacuous or collapsed hypothesis registry. |\n| Discriminator usefulness | Measurement covers candidates and has finite positive cost. | Non-discriminating or unbounded measurement. |\n| Correction authority | Pure diagnosis stays pure; corrective intent names the typed bridge activity. | Direct correction or unknown activity. |\n| Dependable testing | Bounded reproduction, signature, seed where needed, at least two controls and mutants, original plus dependency-cone verification. | Timeout/memory/output/attempt overflow or missing controls. |\n| FPP correspondence | Every intent resolves to Operations component, channel, command, event, and parameter carriers. | Removed mapped component. |\n| Four-surface equivalence | CLI, MCP, and Zenoh normalize to one receipt; UI remains projection-only. | Missing target or divergent receipt. |\n| Bridge digest binding | Typed Swarm intent includes debugging, module, FPP, topology, and exact-head authority digests. | Substituted or stale digest. |\n| Completion | Closed receipt contains root cause, origin, evidence digests, stage, and digest. | Stale verification or skipped phase. |\n\n## Declarative configuration\n\nDebug intents reference configuration only by IDs in `Ops_config.elements`. The integration validator rejects undeclared keys, unknown modules, unknown capabilities, missing FPP carriers, and unregistered bridge activities. No debugging module reads process environment directly.\n";
  Buffer.contents buffer

let render_guide () =
  let buffer = Buffer.create 24576 in
  Buffer.add_string buffer
    (frontmatter ~id:"systematic-debugging" ~title:"Hermes systematic debugging"
       ~ktype:"source"
       ~topics:[ "systematic-debugging"; "operations"; "fpp"; "dependability" ]
       ~links:[ "hermes-systematic-debugging-ontology";
                "hermes-systematic-debugging-fractal-atlas";
                "hermes-systematic-debugging-fractal-algebra";
                "hermes-sop-systematic-debugging" ]);
  Buffer.add_string buffer "# Hermes systematic debugging\n\n";
  Buffer.add_string buffer notice;
  Buffer.add_string buffer
    "## Operator interface\n\n```text\nops completion debug debug.formal-coverage-gap --scope control-plane --request-id REQUEST\nops completion metrics-observe --scope whole-system --request-id REQUEST\nops completion fpp-check --scope whole-system --request-id REQUEST\nops debugging --check\n```\n\nThe first command returns a declared, read-only debugging intent. It does not claim a live root cause and does not modify the repository. Select the intent whose symptom family matches the observation, then execute the generated SOP with real evidence.\n\n## Available intent identities\n\n";
  List.iter
    (fun (item : Debug_intent.t) ->
      Printf.bprintf buffer "- `%s` — %s\n" item.stable_id item.objective)
    Debug_intent.all;
  Buffer.add_string buffer
    "\n## Completion boundary\n\nDiagnosis is complete only when the opaque protocol produces a closed receipt from fresh post-correction evidence. The declared corrective activity is currently `Unavailable_observed`: no corrective graph has been admitted to `Run_swarm_bridge`, so direct mutation is refused. This does not affect pure diagnosis or registry/FPP verification.\n\n## Authorities\n\n- Typed registry and protocol: `modules/hermes_ops/debug_*.ml`.\n- FPP/MBSE projection: `modules/hermes_ops_dashboard/run_topology.ml` and `run_fpp_authority.ml`.\n- Sole effect admission: `modules/hermes_ops_dashboard/run_swarm_bridge.ml`.\n- Cross-agent usage: `.claude/skills/systematic-debugging/SKILL.md`.\n";
  Buffer.contents buffer

let render_sop () =
  let buffer = Buffer.create 24576 in
  Buffer.add_string buffer
    (frontmatter ~id:"sop-systematic-debugging"
       ~title:"SOP: typed systematic debugging" ~ktype:"source"
       ~topics:[ "sop"; "systematic-debugging"; "rca"; "dependability" ]
       ~links:[ "hermes-systematic-debugging";
                "hermes-systematic-debugging-ontology";
                "hermes-systematic-debugging-fractal-atlas" ]);
  Buffer.add_string buffer "# SOP: typed systematic debugging\n\n";
  Buffer.add_string buffer notice;
  Buffer.add_string buffer
    "## Preconditions\n\n1. Capture the exact source head, toolchain receipt, scope, symptom, failing command, and failure signature.\n2. Obtain the declared intent through an Ops surface. Reject an unknown identity or missing target.\n3. Keep diagnosis read-only. Do not execute a correction until a closed activity graph is admitted by `Run_swarm_bridge`.\n\n## Protocol\n\n1. **Declare.** Select one `Debug_intent.t`; record its authority digest, module, FPP mapping, bounds, and success criteria.\n2. **Observe.** Reproduce within the declared timeout/memory/output/attempt envelope. Attach fresh, digested observations with an `L0..L6` coordinate and RCA origin.\n3. **Orient.** Separate the five canonical specification, implementation, environment, evidence, and control origins. Never translate unavailable evidence into implementation failure.\n4. **Hypothesize.** Retain at least two causal explanations with different observable predictions.\n5. **Discriminate.** Run the cheapest bounded measurement that can eliminate at least one candidate. Use controls and mutants to prove the measurement is non-vacuous.\n6. **Correct.** If the cause is established and correction is authorized, synthesize a closed typed activity and submit it only through `Run_swarm_bridge`. While `activity.debug-correction` is unavailable, stop with `Unavailable_observed`; do not bypass the bridge.\n7. **Verify.** Re-run the original reproducer, required controls and mutants, affected dependency cone, FPP correspondence, exact-head gate, and the one-command verification pass.\n8. **Close.** Emit the typed receipt with root cause, origin, evidence digests, terminal stage, and digest. Record remaining unavailable evidence explicitly.\n\n## Required command surfaces\n\n```text\nops completion debug INTENT_ID --scope control-plane --request-id REQUEST\nops debugging --check\ndune exec modules/hermes_ops/ops_main.exe -- verify\n```\n\nThe final verification command is the single R22 offload entrypoint. Do not replace it with a hand-written loop over test executables.\n\n## Refusals\n\n- stale, missing, indeterminate, prose-only, or zero-denominator evidence;\n- one-hypothesis RCA or measurement that cannot distinguish candidates;\n- configuration not declared in `Ops_config.elements`;\n- command, event, channel, parameter, module, capability, or activity identity not present in typed authority;\n- direct SOP execution, raw `Domain` work, generic command fallback, or corrective mutation outside `Run_swarm_bridge`;\n- parity denial from any origin except established Implementation.\n";
  Buffer.contents buffer

let surfaces () =
  [ (guide_path, render_guide ()); (sop_path, render_sop ());
    (ontology_path, render_ontology ()); (atlas_path, render_atlas ());
    (algebra_path, render_algebra ()) ]

let read_file path =
  try
    let channel = open_in_bin path in
    Fun.protect ~finally:(fun () -> close_in_noerr channel)
      (fun () -> Some (really_input_string channel (in_channel_length channel)))
  with Sys_error _ -> None

let drifted () =
  surfaces ()
  |> List.filter_map (fun (path, expected) ->
         match read_file path with
         | Some observed when String.equal observed expected -> None
         | Some _ -> Some (path ^ ": stale")
         | None -> Some (path ^ ": missing"))

let write_file path body =
  let temporary = path ^ ".tmp" in
  try
    let channel = open_out_bin temporary in
    Fun.protect ~finally:(fun () -> close_out_noerr channel)
      (fun () -> output_string channel body);
    Sys.rename temporary path;
    Ok ()
  with Sys_error message -> Error (path ^ ": " ^ message)

let write () =
  let rec loop = function
    | [] -> Ok "wrote systematic debugging guide, SOP, ontology, atlas, and algebra"
    | (path, body) :: rest ->
        begin match write_file path body with
        | Ok () -> loop rest
        | Error _ as error -> error
        end
  in
  loop (surfaces ())

let check () =
  let findings = drifted () in
  let output =
    String.concat "" (List.map (fun item -> "DOC DRIFT: " ^ item ^ "\n") findings)
    ^ Printf.sprintf "systematic debugging docs: %d surfaces, %d drift finding(s)\n"
        (List.length (surfaces ())) (List.length findings)
  in
  (output, if findings = [] then 0 else 1)
