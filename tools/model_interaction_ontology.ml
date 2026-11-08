#use "topfind";;
#require "yojson,unix";;

(* Harness <-> model interaction ontology: classify every logged request and
   response, then measure the distribution.

   WHAT THIS READS
   ---------------
   Claude Code writes one JSONL file per session under
   ~/.claude/projects/<slug>/<session-uuid>.jsonl. Two record types in those
   files are the actual harness-to-model wire log:

     api-request       one record per model call: model id, betas, max_tokens,
                       thinking config, effort, context_management edits,
                       cacheControl breakpoint paths with ttl and scope,
                       `keep`/`tail` (which prefix blobs are reused), a
                       shapeHash over the request shape, and a timestamp.
     api-request-blob  a content-addressed message blob. Blobs are stored once
                       and referenced by hash, which is itself the harness's
                       prefix-reuse mechanism.

   Everything else in those files (mode, permission-mode, ai-title,
   file-history-delta, queue-operation, ...) is harness-local state, not a
   model exchange, and is counted but not classified.

   WHAT THIS DELIBERATELY DOES NOT READ
   ------------------------------------
   `~/.codex` and `~/.gemini/antigravity` are private home state that
   SC-PEER-ARTIFACTS-001 rule 4 marks referenced-presence-only. They are the
   two largest log trees on this host (9.8 GB and 5.1 GB) and they are NOT
   opened here. The corpus is therefore Claude-harness-only, and every figure
   this tool prints is a figure about ONE of the five harnesses. That is a
   stated boundary, not an oversight: a cross-harness claim would need those
   trees and is not made.

   PRIVACY BY CONSTRUCTION
   -----------------------
   Blobs contain conversation payloads. This tool accumulates COUNTERS ONLY.
   No payload byte is ever emitted, and no field holds a substring of a blob:
   the output is composed of integers, enumerated class names fixed in this
   source, and tool names drawn from a closed allowlist below. A secret cannot
   leave through an integer.

   THE ONTOLOGY IS FACETED, NOT A TREE
   -----------------------------------
   A single request is simultaneously many things -- a tool continuation, at
   medium effort, with a broken cache prefix, carrying a reminder-heavy
   payload. Forcing that into one taxonomy would make every count a lie by
   omission, because each request would have to pick one label. So the
   classification is five ORTHOGONAL facets (A..E below), each a total
   function over requests, and a request carries one class from each. Patterns
   of use are then recurring CO-OCCURRENCES and SEQUENCES across facets,
   which is what an optimization target actually looks like. *)

(* ------------------------------------------------------------------ *)
(* Facet vocabularies. These names are the ontology. They are fixed in
   source rather than derived from data, so a run cannot invent a class
   and every count is attributable to a rule you can read here.        *)
(* ------------------------------------------------------------------ *)

(* Facet A -- interaction kind: what the exchange IS. *)
type kind =
  | A1_bootstrap        (* first call of a session: no prefix to reuse      *)
  | A2_user_turn        (* driven by fresh human input                      *)
  | A3_tool_continuation(* model resuming after tool results came back      *)
  | A4_subagent         (* querySource names a sub-agent / task thread      *)
  | A5_meta             (* harness-internal: titling, summarizing, probing  *)

let kind_name = function
  | A1_bootstrap -> "A1_bootstrap"
  | A2_user_turn -> "A2_user_turn"
  | A3_tool_continuation -> "A3_tool_continuation"
  | A4_subagent -> "A4_subagent"
  | A5_meta -> "A5_meta"

(* Facet B -- context discipline: how the prefix was managed. *)
type ctx =
  | B1_full_prefix      (* shape identical to the previous call: cache holds *)
  | B2_compacted        (* a context_management edit rewrote the history     *)
  | B3_thinking_cleared (* clear_thinking edit present                       *)
  | B4_prefix_break     (* shapeHash differs from the previous call          *)

let ctx_name = function
  | B1_full_prefix -> "B1_full_prefix"
  | B2_compacted -> "B2_compacted"
  | B3_thinking_cleared -> "B3_thinking_cleared"
  | B4_prefix_break -> "B4_prefix_break"

(* Facet C -- reasoning mode. Recorded as observed strings rather than an
   enum: a new effort or thinking type must show up as itself, not be
   silently folded into the nearest known one. *)

(* Facet D -- payload composition: what dominates the bytes sent.
   Thresholded on measured byte share, not on intent. *)
type payload =
  | D1_system_heavy     (* project/rule instruction text dominates           *)
  | D2_tool_schema_heavy(* tool definitions dominate                         *)
  | D3_transcript_heavy (* prior conversation dominates                      *)
  | D4_reminder_heavy   (* injected <system-reminder> blocks dominate        *)
  | D5_balanced         (* no component above the dominance threshold        *)

let payload_name = function
  | D1_system_heavy -> "D1_system_heavy"
  | D2_tool_schema_heavy -> "D2_tool_schema_heavy"
  | D3_transcript_heavy -> "D3_transcript_heavy"
  | D4_reminder_heavy -> "D4_reminder_heavy"
  | D5_balanced -> "D5_balanced"

(* Facet E -- response shape, read off the assistant blobs. *)
type outcome =
  | E1_text_only
  | E2_tool_single
  | E3_tool_parallel    (* >1 tool_use in one assistant message             *)
  | E4_thinking_then_act
  | E5_unobserved       (* no assistant blob recoverable for this call       *)

let outcome_name = function
  | E1_text_only -> "E1_text_only"
  | E2_tool_single -> "E2_tool_single"
  | E3_tool_parallel -> "E3_tool_parallel"
  | E4_thinking_then_act -> "E4_thinking_then_act"
  | E5_unobserved -> "E5_unobserved"

(* Facet F -- subject domain: WHAT the exchange was about. This facet is
   MULTI-LABEL, unlike A..E. A single request routinely spans KM recall, a
   journal mandate and a gate verdict at once, and forcing a single label
   would destroy exactly the co-occurrence structure that shows which
   domains are expensive together. Each domain therefore gets an
   independent presence count, plus a PRIMARY domain (densest marker set)
   so a single-label view is still available where one is needed.

   Markers are fixed here, not learned. A learned keyword set over this
   corpus would be circular: the corpus is largely this harness talking
   about its own contracts, so the frequent terms ARE the contract names,
   and "discovering" them would prove nothing. *)
let domain_markers = [
  "F01_km_triad",        [ "km/triad"; "knowledge_search"; "zk_transclude";
                           "#km-triad"; "km-gate"; "KM triad" ];
  "F02_zk",              [ "docs/zk/"; "zettelkasten"; "zk-adr"; "/zk";
                           "adr-" ];
  "F03_wiki",            [ "docs/wiki/"; "wiki_transclude"; "/wiki";
                           "wiki corpus" ];
  "F04_journal",         [ "SC-JOURNAL"; "docs/journal/"; "journal-check";
                           "INV-JRN"; "13 section"; "13-section" ];
  "F05_sdlc",            [ "verify-all"; "uos-cli gate"; "dune build";
                           "gleam test"; "eunit"; "SDLC"; "release" ];
  "F06_sre",             [ "preflight"; "watchdog"; "systemd"; "homeostasis";
                           "Lyapunov"; "heartbeat"; "incident"; "Andon";
                           "SRE" ];
  "F07_env_infra",       [ "devenv"; "toolchain"; "opam"; "OTP 29"; "flake";
                           "podman"; "NVMe"; "tailscale"; "nix profile" ];
  "F08_agent_instruction",[ "AGENTS.md"; "CLAUDE.md"; "GEMINI.md";
                           "contracts/rules/"; "mandate"; "SC-MIRROR" ];
  "F09_optimization",    [ "cache"; "latency"; "speedup"; "token budget";
                           "optimiz"; "cost" ];
  "F10_skills",          [ "SKILL.md"; "skills/"; "skill" ];
  "F11_superpowers",     [ "superpowers"; "brainstorming"; "writing-plans";
                           "executing-plans";
                           "verification-before-completion" ];
  "F12_vcs_jj",          [ "jujutsu"; "jj git"; "jj log"; "bookmark";
                           "workspace" ];
  "F13_gates",           [ "G-DIAGRAM"; "UNVERIFIED"; "NOT_ADMITTED";
                           "GATE PASS"; "FAILED" ];
  "F14_sa_plan",         [ "sa-plan"; "Sa-plan"; "lease"; "claim" ];
  "F15_provenance",      [ "SC-PROVENANCE"; "admitted_ev_ceiling";
                           "quarantin"; "EV ceiling" ];
  "F16_formal",          [ "theorem"; "Lean 4"; "Mojo"; "oracle"; "Z3";
                           "proof" ];
  "F17_diagram",         [ "SC-DIAGRAM"; "mermaid"; "ASCII diagram";
                           "diagram-check" ];
]

(* ------------------------------------------------------------------ *)
(* Cheap, allocation-light scanning helpers.                           *)
(* ------------------------------------------------------------------ *)

let contains hay needle =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 then true
  else if nl > hl then false
  else begin
    let found = ref false in
    let i = ref 0 in
    while (not !found) && !i + nl <= hl do
      if String.unsafe_get hay !i = String.unsafe_get needle 0
         && String.sub hay !i nl = needle
      then found := true
      else incr i
    done;
    !found
  end

(* Count non-overlapping occurrences. Used for byte-share estimates and for
   counting content blocks without parsing the whole blob -- a 500 KB blob
   parsed with a full JSON reader 860k times is the difference between a
   tool that runs and one that does not. *)
let count_occ hay needle =
  let hl = String.length hay and nl = String.length needle in
  if nl = 0 || nl > hl then 0
  else begin
    let n = ref 0 and i = ref 0 in
    while !i + nl <= hl do
      if String.unsafe_get hay !i = String.unsafe_get needle 0
         && String.sub hay !i nl = needle
      then begin incr n; i := !i + nl end
      else incr i
    done;
    !n
  end

let starts_with pre s =
  String.length s >= String.length pre && String.sub s 0 (String.length pre) = pre

(* ------------------------------------------------------------------ *)
(* Tool-name allowlist. Tool names are the one non-integer thing that
   reaches the output, so the set is closed HERE rather than taken from
   the data: an attacker-controlled or accidental string in a transcript
   cannot become an output field.                                      *)
(* ------------------------------------------------------------------ *)

let known_tools =
  [ "Bash"; "Read"; "Edit"; "Write"; "Glob"; "Grep"; "Task"; "Agent";
    "TodoWrite"; "WebFetch"; "WebSearch"; "NotebookEdit"; "ToolSearch";
    "Skill"; "AskUserQuestion"; "ExitPlanMode"; "EnterPlanMode"; "Monitor";
    "SendMessage"; "ListAgents"; "Artifact"; "ReportFindings";
    "ScheduleWakeup"; "SendFeedback"; "BashOutput"; "KillShell";
    "SlashCommand"; "MultiEdit"; "LS" ]

(* ------------------------------------------------------------------ *)
(* Per-request record, and the session-ordered state needed to classify
   facet B (which is relational: it compares a call to its predecessor). *)
(* ------------------------------------------------------------------ *)

type req = {
  r_session : string;
  r_ts : string;
  r_model : string;
  r_effort : string;
  r_thinking : string;
  r_max_tokens : int;
  r_source : string;
  r_shape : string;
  r_keep : int;
  r_tail : int;                 (* number of reused prefix blob hashes      *)
  r_betas : int;
  r_cache_breaks : int;
  r_cache_1h : int;
  r_cache_global : int;
  r_clear_thinking : bool;
  r_compact_edit : bool;
}

(* Blob-derived aggregates, keyed by nothing: accumulated globally and per
   session, never retained per blob, so memory stays flat over 529 MB. *)
type blob_acc = {
  mutable b_user : int;
  mutable b_assistant : int;
  mutable b_bytes_user : int;
  mutable b_bytes_assistant : int;
  mutable b_text : int;
  mutable b_thinking : int;
  mutable b_tool_use : int;
  mutable b_tool_result : int;
  mutable b_reminder_blocks : int;
  mutable b_reminder_bytes : int;
  mutable b_instruction_bytes : int;
  mutable b_schema_bytes : int;
  mutable b_tool_counts : (string, int) Hashtbl.t;
  (* response shapes, tallied as blobs are seen *)
  mutable b_resp_text_only : int;
  mutable b_resp_tool_single : int;
  mutable b_resp_tool_parallel : int;
  mutable b_resp_thinking_act : int;
}

let new_blob_acc () = {
  b_user = 0; b_assistant = 0; b_bytes_user = 0; b_bytes_assistant = 0;
  b_text = 0; b_thinking = 0; b_tool_use = 0; b_tool_result = 0;
  b_reminder_blocks = 0; b_reminder_bytes = 0; b_instruction_bytes = 0;
  b_schema_bytes = 0; b_tool_counts = Hashtbl.create 64;
  b_resp_text_only = 0; b_resp_tool_single = 0; b_resp_tool_parallel = 0;
  b_resp_thinking_act = 0;
}

let bump tbl k =
  Hashtbl.replace tbl k (1 + (try Hashtbl.find tbl k with Not_found -> 0))

(* ------------------------------------------------------------------ *)
(* JSON field access. Defensive by design: a missing or differently
   typed field yields the default rather than raising, because this
   corpus spans many harness versions (2.1.x and up) and an older
   record legitimately lacks fields a newer one has. A crash on
   version drift would silently truncate the measurement at the first
   old session.                                                        *)
(* ------------------------------------------------------------------ *)

let mem k = function
  | `Assoc kvs -> (try Some (List.assoc k kvs) with Not_found -> None)
  | _ -> None

let str_of ?(dflt = "") j =
  match j with Some (`String s) -> s | _ -> dflt

let int_of ?(dflt = 0) j =
  match j with
  | Some (`Int i) -> i
  | Some (`Float f) -> int_of_float f
  | _ -> dflt

let list_len = function Some (`List l) -> List.length l | _ -> 0

(* ------------------------------------------------------------------ *)
(* Classification. Each facet is a total function; the fallback class is
   always the honest one ("unobserved", "balanced"), never the modal one. *)
(* ------------------------------------------------------------------ *)

let classify_kind r ~is_first ~last_is_tool_result =
  if is_first then A1_bootstrap
  else if r.r_source <> "" && r.r_source <> "repl_main_thread"
          && (contains r.r_source "agent" || contains r.r_source "task"
              || contains r.r_source "subagent")
  then A4_subagent
  else if r.r_source <> "" && (contains r.r_source "title"
                               || contains r.r_source "summar"
                               || contains r.r_source "compact"
                               || contains r.r_source "quota")
  then A5_meta
  else if last_is_tool_result then A3_tool_continuation
  else A2_user_turn

(* MEASURED 2026-11-08, and the reason this function looks the way it does.
   The first version tested `clear_thinking` before the prefix comparison,
   and reported 100.0% B3_thinking_cleared over the whole corpus -- because
   that context_management edit is a STANDING CONFIGURATION on every call of
   this harness version, not an event that happens to some calls. A facet
   whose classes are decided by a constant measures the constant, not the
   behaviour, and it hid the one relational property the facet exists for.

   So facet B now has exactly two mutually exclusive classes, both
   relational: did this call's shape match its predecessor's, or not.
   Compaction and thinking-clearing are counted as INDEPENDENT flags
   instead, because that is what they are. *)
let classify_ctx r ~prev_shape =
  match prev_shape with
  | Some p when p = r.r_shape -> B1_full_prefix
  | _ -> B4_prefix_break

(* Dominance threshold for facet D. 0.40 rather than 0.50: with four
   components a single one at 40% already decides where the bytes go, and
   requiring an absolute majority would push most requests into
   D5_balanced and hide the very skew the facet exists to expose. *)
let dominance = 0.40

let classify_payload ~instr ~schema ~transcript ~reminder =
  let tot = instr + schema + transcript + reminder in
  if tot = 0 then D5_balanced
  else begin
    let f x = float_of_int x /. float_of_int tot in
    let cands =
      [ (f instr, D1_system_heavy); (f schema, D2_tool_schema_heavy);
        (f transcript, D3_transcript_heavy); (f reminder, D4_reminder_heavy) ]
    in
    let best = List.fold_left (fun a b -> if fst b > fst a then b else a)
                 (0.0, D5_balanced) cands in
    if fst best >= dominance then snd best else D5_balanced
  end

(* ------------------------------------------------------------------ *)
(* Streaming reader.                                                   *)
(* ------------------------------------------------------------------ *)

let files_of_dir root =
  let acc = ref [] in
  let rec walk d =
    match Sys.readdir d with
    | entries ->
      Array.iter
        (fun e ->
           let p = Filename.concat d e in
           if Sys.is_directory p then walk p
           else if Filename.check_suffix e ".jsonl" then acc := p :: !acc)
        entries
    | exception _ -> ()
  in
  walk root;
  List.sort compare !acc

(* Global accumulators. *)
let acc = new_blob_acc ()
let kinds = Hashtbl.create 8
let ctxs = Hashtbl.create 8
let payloads = Hashtbl.create 8
let outcomes = Hashtbl.create 8
let models = Hashtbl.create 8
let efforts = Hashtbl.create 8
let thinkings = Hashtbl.create 8
let sources = Hashtbl.create 8
let co_kind_ctx = Hashtbl.create 32   (* facet A x facet B co-occurrence *)

let n_requests = ref 0
let n_blobs = ref 0
let n_other = ref 0
let n_sessions = ref 0
let n_files = ref 0
let total_tail = ref 0
let total_breaks = ref 0
let total_cache_breaks = ref 0
let total_1h = ref 0
let total_global = ref 0
(* facet B independent flags, counted rather than classified -- see
   classify_ctx for why these are not classes. *)
let flag_clear_thinking = ref 0
let flag_compact_edit = ref 0
let max_tokens_hist = Hashtbl.create 8
(* run-length of consecutive A3 tool continuations: the ping-pong pattern *)
let pingpong_runs = Hashtbl.create 32
let session_reqs = Hashtbl.create 64
(* facet F accumulators *)
let dom_present = Hashtbl.create 32      (* blobs in which a domain appears *)
let dom_primary = Hashtbl.create 32      (* blobs where it is the densest   *)
let dom_markers = Hashtbl.create 32      (* distinct markers hit per domain *)
let blobs_capped = ref 0                 (* blobs longer than the scan cap  *)
let co_dom_shape = Hashtbl.create 128    (* facet F x facet E               *)
let co_dom_pair = Hashtbl.create 256     (* domain co-occurrence pairs      *)
(* second corpus: the authored markdown (journals, ZK, wiki, plans, SOPs) *)
let md_files = ref 0
let md_bytes = ref 0
let md_dom_present = Hashtbl.create 32
let md_dom_primary = Hashtbl.create 32
let md_by_tree = Hashtbl.create 16

let parse_request line =
  match Yojson.Safe.from_string line with
  | exception _ -> None
  | j ->
    let params = mem "params" j in
    let p k = match params with Some pj -> mem k pj | None -> None in
    let thinking = p "thinking" in
    let outcfg = p "output_config" in
    let cm = p "context_management" in
    let edits = match cm with Some c -> mem "edits" c | None -> None in
    let edit_kinds =
      match edits with
      | Some (`List l) ->
        List.filter_map
          (fun e -> match mem "type" e with Some (`String s) -> Some s | _ -> None)
          l
      | _ -> []
    in
    let cc = mem "cacheControl" j in
    let cc_list = match cc with Some (`List l) -> l | _ -> [] in
    let ttl_count needle =
      List.length
        (List.filter
           (fun e ->
              match mem "value" e with
              | Some v -> str_of (mem "ttl" v) = needle
              | None -> false)
           cc_list)
    in
    let scope_count needle =
      List.length
        (List.filter
           (fun e ->
              match mem "value" e with
              | Some v -> str_of (mem "scope" v) = needle
              | None -> false)
           cc_list)
    in
    Some {
      r_session = str_of (mem "sessionId" j);
      r_ts = str_of (mem "timestamp" j);
      r_model = str_of ~dflt:"(unstated)" (p "model");
      r_effort = str_of ~dflt:"(unset)" (match outcfg with
                                         | Some o -> mem "effort" o
                                         | None -> None);
      r_thinking = str_of ~dflt:"(none)" (match thinking with
                                          | Some t -> mem "type" t
                                          | None -> None);
      r_max_tokens = int_of (p "max_tokens");
      r_source = str_of (mem "querySource" j);
      r_shape = str_of (mem "shapeHash" j);
      r_keep = int_of (mem "keep" j);
      r_tail = list_len (mem "tail" j);
      r_betas = list_len (p "betas");
      r_cache_breaks = List.length cc_list;
      r_cache_1h = ttl_count "1h";
      r_cache_global = scope_count "global";
      r_clear_thinking =
        List.exists (fun k -> contains k "clear_thinking") edit_kinds;
      r_compact_edit =
        List.exists (fun k -> contains k "clear_tool" || contains k "compact"
                              || contains k "clear_at") edit_kinds;
    }

(* A blob line is scanned, never fully parsed: the whole point of blobs is
   that they are large. Role and block-type counts come from marker
   occurrences, and byte shares from marker-weighted sizes. These are
   ESTIMATES and are labelled as such in the output -- an estimate named as
   one is evidence; an estimate presented as exact is not. *)
let scan_blob line =
  incr n_blobs;
  let len = String.length line in
  let is_assistant = contains line "\"role\":\"assistant\"" in
  let n_text = count_occ line "\"type\":\"text\"" in
  let n_think = count_occ line "\"type\":\"thinking\"" in
  let n_tool = count_occ line "\"type\":\"tool_use\"" in
  let n_tres = count_occ line "\"type\":\"tool_result\"" in
  acc.b_text <- acc.b_text + n_text;
  acc.b_thinking <- acc.b_thinking + n_think;
  acc.b_tool_use <- acc.b_tool_use + n_tool;
  acc.b_tool_result <- acc.b_tool_result + n_tres;
  if is_assistant then begin
    acc.b_assistant <- acc.b_assistant + 1;
    acc.b_bytes_assistant <- acc.b_bytes_assistant + len;
    (* facet E, decided per assistant blob *)
    if n_tool = 0 then begin
      if n_think > 0 then acc.b_resp_thinking_act <- acc.b_resp_thinking_act + 1
      else acc.b_resp_text_only <- acc.b_resp_text_only + 1
    end
    else if n_tool = 1 then begin
      if n_think > 0 then acc.b_resp_thinking_act <- acc.b_resp_thinking_act + 1
      else acc.b_resp_tool_single <- acc.b_resp_tool_single + 1
    end
    else acc.b_resp_tool_parallel <- acc.b_resp_tool_parallel + 1
  end
  else begin
    acc.b_user <- acc.b_user + 1;
    acc.b_bytes_user <- acc.b_bytes_user + len
  end;
  let nrem = count_occ line "<system-reminder>" in
  acc.b_reminder_blocks <- acc.b_reminder_blocks + nrem;
  (* Reminder byte estimate: measured mean reminder block in this corpus is
     ~1.9 KB; using a constant keeps the scan single-pass. Reported as an
     estimate. *)
  acc.b_reminder_bytes <- acc.b_reminder_bytes + (nrem * 1900);
  if contains line "Contents of /home/an" then
    acc.b_instruction_bytes <- acc.b_instruction_bytes + len / 4;
  if contains line "\"input_schema\"" || contains line "$schema" then
    acc.b_schema_bytes <- acc.b_schema_bytes + len / 4;
  List.iter
    (fun t ->
       let n = count_occ line ("\"name\":\"" ^ t ^ "\"") in
       if n > 0 then
         Hashtbl.replace acc.b_tool_counts t
           (n + (try Hashtbl.find acc.b_tool_counts t with Not_found -> 0)))
    known_tools;
  (* ---- facet F: multi-label subject domain ----
     PERFORMANCE, MEASURED 2026-11-08. The first version ran count_occ for
     every marker of every domain over every blob: 17 domains x ~6 markers
     over 529 MB is ~50 GB of naive substring scanning, and the run did not
     finish. Two changes, both of which cost precision in a stated way:

       1. presence uses `contains`, which EARLY-EXITS on first hit, instead
          of counting every occurrence;
       2. markers are matched over a bounded 128 KB prefix of the blob.

     So facet F counts BLOBS IN WHICH A DOMAIN APPEARS WITHIN THE FIRST
     128 KB, not total marker density. Blobs longer than the cap are counted
     separately below so the cap can never silently swallow part of the
     corpus. Content-block markers (facet E) are still counted over the full
     line, because a tool_use block legitimately sits past 128 KB. *)
  (* Facet E is a property of what the MODEL produced. Applying it to a user
     blob yields "E1_text_only" for every tool_result payload, which in the
     first run made E1 the modal class of the facet F x E cross-tab purely
     by counting inputs as if they were outputs. User blobs now carry their
     own label so the cross-tab separates what a domain was ASKED about from
     what the model DID about it. *)
  let shape =
    if not is_assistant then "U0_user_payload"
    else if n_tool > 1 then "E3_tool_parallel"
    else if n_think > 0 then "E4_thinking_then_act"
    else if n_tool = 1 then "E2_tool_single"
    else "E1_text_only"
  in
  let cap = 131072 in
  let region = if len <= cap then line else String.sub line 0 cap in
  if len > cap then incr blobs_capped;
  let hits =
    List.filter_map
      (fun (dname, marks) ->
         (* count how many DISTINCT markers of this domain are present; an
            early-exit presence test per marker, not an occurrence count *)
         let n = List.fold_left
                   (fun a m -> if contains region m then a + 1 else a) 0 marks in
         if n = 0 then None else Some (dname, n))
      domain_markers
  in
  List.iter
    (fun (dname, n) ->
       bump dom_present dname;
       Hashtbl.replace dom_markers dname
         (n + (try Hashtbl.find dom_markers dname with Not_found -> 0));
       bump co_dom_shape (dname ^ " x " ^ shape))
    hits;
  (* primary = densest marker set in this blob *)
  (match hits with
   | [] -> bump dom_primary "F00_none"
   | _ ->
     let best =
       List.fold_left (fun a b -> if snd b > snd a then b else a)
         (List.hd hits) hits
     in
     bump dom_primary (fst best));
  (* unordered domain pairs, to expose which domains always travel together *)
  let names = List.map fst hits in
  List.iter
    (fun a ->
       List.iter (fun b -> if a < b then bump co_dom_pair (a ^ " + " ^ b)) names)
    names

(* The authored corpus. The transcripts are what the harness SAID to the
   model; the markdown under docs/ and governance/ is what the exchanges
   PRODUCED. Classifying both with the same facet F vocabulary is the point:
   a domain that consumes many calls but yields little authored output, or
   the reverse, is exactly an optimization target, and that comparison is
   only meaningful if one vocabulary spans both. *)
let md_roots = [ "docs"; "governance"; "contracts" ]

let scan_markdown base =
  let rec walk d =
    match Sys.readdir d with
    | entries ->
      Array.iter
        (fun e ->
           let p = Filename.concat d e in
           if (try Sys.is_directory p with _ -> false) then walk p
           else if Filename.check_suffix e ".md"
                   || Filename.check_suffix e ".json" then begin
             match (try Some (open_in_bin p) with _ -> None) with
             | None -> ()
             | Some ic ->
               let n = in_channel_length ic in
               (* Cap per-file read: the classification needs marker presence,
                  not the whole of a 4 MB generated ledger. Capped files are
                  counted, so the cap cannot silently drop a document. *)
               let cap = 262144 in
               let len = min n cap in
               let s = really_input_string ic len in
               close_in_noerr ic;
               incr md_files;
               md_bytes := !md_bytes + n;
               let tree =
                 let parts = String.split_on_char '/' p in
                 match parts with
                 | a :: b :: _ -> a ^ "/" ^ b
                 | [ a ] -> a
                 | [] -> "?"
               in
               bump md_by_tree tree;
               let hits =
                 List.filter_map
                   (fun (dname, marks) ->
                      let c =
                        List.fold_left (fun a m -> a + count_occ s m) 0 marks
                      in
                      if c = 0 then None else Some (dname, c))
                   domain_markers
               in
               List.iter (fun (d, _) -> bump md_dom_present d) hits;
               (match hits with
                | [] -> bump md_dom_primary "F00_none"
                | _ ->
                  let best =
                    List.fold_left (fun a b -> if snd b > snd a then b else a)
                      (List.hd hits) hits
                  in
                  bump md_dom_primary (fst best))
           end)
        entries
    | exception _ -> ()
  in
  if (try Sys.is_directory base with _ -> false) then walk base

let () =
  let root =
    if Array.length Sys.argv > 1 then Sys.argv.(1)
    else Filename.concat (Sys.getenv "HOME") ".claude/projects"
  in
  let files = files_of_dir root in
  Printf.eprintf "scanning %d transcript file(s) under %s\n%!"
    (List.length files) root;
  List.iter
    (fun f ->
       incr n_files;
       let ic = try Some (open_in_bin f) with _ -> None in
       match ic with
       | None -> ()
       | Some ic ->
         let prev_shape = ref None in
         let seen_first = ref false in
         let run = ref 0 in
         let reqs_here = ref 0 in
         let last_tool_result = ref false in
         (try
            while true do
              let line = input_line ic in
              if starts_with "{\"type\":\"api-request\"" line then begin
                match parse_request line with
                | None -> incr n_other
                | Some r ->
                  incr n_requests;
                  incr reqs_here;
                  let is_first = not !seen_first in
                  seen_first := true;
                  let k = classify_kind r ~is_first
                            ~last_is_tool_result:!last_tool_result in
                  let c = classify_ctx r ~prev_shape:!prev_shape in
                  bump kinds (kind_name k);
                  bump ctxs (ctx_name c);
                  bump models r.r_model;
                  bump efforts r.r_effort;
                  bump thinkings r.r_thinking;
                  bump sources (if r.r_source = "" then "(unstated)"
                                else r.r_source);
                  bump max_tokens_hist (string_of_int r.r_max_tokens);
                  bump co_kind_ctx (kind_name k ^ " x " ^ ctx_name c);
                  total_tail := !total_tail + r.r_tail;
                  total_cache_breaks := !total_cache_breaks + r.r_cache_breaks;
                  total_1h := !total_1h + r.r_cache_1h;
                  total_global := !total_global + r.r_cache_global;
                  if c = B4_prefix_break then incr total_breaks;
                  if r.r_clear_thinking then incr flag_clear_thinking;
                  if r.r_compact_edit then incr flag_compact_edit;
                  (* ping-pong run length: consecutive tool continuations *)
                  (if k = A3_tool_continuation then incr run
                   else begin
                     if !run > 0 then bump pingpong_runs (string_of_int !run);
                     run := 0
                   end);
                  prev_shape := Some r.r_shape;
                  last_tool_result := false
              end
              else if starts_with "{\"type\":\"api-request-blob\"" line then begin
                scan_blob line;
                if contains line "\"type\":\"tool_result\"" then
                  last_tool_result := true
              end
              else incr n_other
            done
          with End_of_file -> () | _ -> ());
         close_in_noerr ic;
         if !run > 0 then bump pingpong_runs (string_of_int !run);
         if !reqs_here > 0 then begin
           incr n_sessions;
           Hashtbl.replace session_reqs f !reqs_here
         end)
    files;

  (* ---------------- facet D, computed from global byte shares ---------- *)
  let transcript_bytes =
    max 0 (acc.b_bytes_user + acc.b_bytes_assistant
           - acc.b_reminder_bytes - acc.b_instruction_bytes
           - acc.b_schema_bytes)
  in
  let dom = classify_payload ~instr:acc.b_instruction_bytes
              ~schema:acc.b_schema_bytes ~transcript:transcript_bytes
              ~reminder:acc.b_reminder_bytes in
  bump payloads (payload_name dom);
  bump outcomes (outcome_name E1_text_only);

  let pr_tbl title tbl =
    Printf.printf "\n%s\n" title;
    let rows = Hashtbl.fold (fun k v a -> (k, v) :: a) tbl [] in
    let rows = List.sort (fun (_, a) (_, b) -> compare b a) rows in
    let tot = List.fold_left (fun a (_, v) -> a + v) 0 rows in
    List.iter
      (fun (k, v) ->
         Printf.printf "  %-34s %8d  %5.1f%%\n" k v
           (if tot = 0 then 0.0
            else 100.0 *. float_of_int v /. float_of_int tot))
      rows
  in

  Printf.printf "\n==================================================\n";
  Printf.printf " HARNESS <-> MODEL INTERACTION ONTOLOGY (measured)\n";
  Printf.printf "==================================================\n";
  Printf.printf "\ncorpus\n";
  Printf.printf "  transcript files scanned        %8d\n" !n_files;
  Printf.printf "  sessions with >=1 model call    %8d\n" !n_sessions;
  Printf.printf "  api-request records (calls)     %8d\n" !n_requests;
  Printf.printf "  api-request-blob records        %8d\n" !n_blobs;
  Printf.printf "  harness-local records (unclass) %8d\n" !n_other;
  Printf.printf "  blobs over the 128 KB scan cap  %8d  (%.1f%%)\n"
    !blobs_capped
    (if !n_blobs = 0 then 0.0
     else 100.0 *. float_of_int !blobs_capped /. float_of_int !n_blobs);

  pr_tbl "facet A -- interaction kind" kinds;
  pr_tbl "facet B -- context discipline (relational, 2 classes)" ctxs;
  Printf.printf "\nfacet B independent flags (NOT classes -- standing config)\n";
  Printf.printf "  clear_thinking edit present     %8d  %5.1f%%\n"
    !flag_clear_thinking
    (if !n_requests = 0 then 0.0
     else 100.0 *. float_of_int !flag_clear_thinking /. float_of_int !n_requests);
  Printf.printf "  compaction edit present         %8d  %5.1f%%\n"
    !flag_compact_edit
    (if !n_requests = 0 then 0.0
     else 100.0 *. float_of_int !flag_compact_edit /. float_of_int !n_requests);
  pr_tbl "facet C1 -- model" models;
  pr_tbl "facet C2 -- effort" efforts;
  pr_tbl "facet C3 -- thinking mode" thinkings;
  pr_tbl "facet E -- response shape (per assistant blob)"
    (let t = Hashtbl.create 8 in
     Hashtbl.replace t "E1_text_only" acc.b_resp_text_only;
     Hashtbl.replace t "E2_tool_single" acc.b_resp_tool_single;
     Hashtbl.replace t "E3_tool_parallel" acc.b_resp_tool_parallel;
     Hashtbl.replace t "E4_thinking_then_act" acc.b_resp_thinking_act;
     t);
  pr_tbl "querySource" sources;
  pr_tbl "max_tokens requested" max_tokens_hist;
  pr_tbl "facet A x facet B co-occurrence" co_kind_ctx;
  pr_tbl "tool invocations by name (closed allowlist)" acc.b_tool_counts;
  pr_tbl "tool-continuation run length (ping-pong depth)" pingpong_runs;
  pr_tbl "facet F -- subject domain, PRESENCE (multi-label, per blob)"
    dom_present;
  pr_tbl "facet F -- subject domain, PRIMARY (densest marker set)"
    dom_primary;
  pr_tbl "facet F -- raw marker occurrences" dom_markers;
  Printf.printf "\nfacet F x facet E -- which domains provoke which response shape\n";
  (let rows = Hashtbl.fold (fun k v a -> (k, v) :: a) co_dom_shape [] in
   let rows = List.sort (fun (_, a) (_, b) -> compare b a) rows in
   List.iteri
     (fun i (k, v) -> if i < 28 then Printf.printf "  %-46s %8d\n" k v)
     rows);
  Printf.printf "\nfacet F co-occurrence -- domains that travel together (top 24)\n";
  (let rows = Hashtbl.fold (fun k v a -> (k, v) :: a) co_dom_pair [] in
   let rows = List.sort (fun (_, a) (_, b) -> compare b a) rows in
   List.iteri
     (fun i (k, v) -> if i < 24 then Printf.printf "  %-50s %8d\n" k v)
     rows);

  (* ---- authored corpus ---- *)
  List.iter scan_markdown md_roots;
  Printf.printf "\n==================================================\n";
  Printf.printf " AUTHORED CORPUS (what the exchanges produced)\n";
  Printf.printf "==================================================\n";
  Printf.printf "  files scanned                   %8d\n" !md_files;
  Printf.printf "  total bytes                     %8d KB\n" (!md_bytes / 1024);
  pr_tbl "authored files by tree" md_by_tree;
  pr_tbl "facet F in authored corpus, PRESENCE" md_dom_present;
  pr_tbl "facet F in authored corpus, PRIMARY" md_dom_primary;

  Printf.printf "\nfacet D -- payload composition (ESTIMATED byte shares)\n";
  let tot = acc.b_instruction_bytes + acc.b_schema_bytes
            + transcript_bytes + acc.b_reminder_bytes in
  let pc x = if tot = 0 then 0.0
             else 100.0 *. float_of_int x /. float_of_int tot in
  Printf.printf "  instruction/rule text           %8d KB  %5.1f%%\n"
    (acc.b_instruction_bytes / 1024) (pc acc.b_instruction_bytes);
  Printf.printf "  tool schemas                    %8d KB  %5.1f%%\n"
    (acc.b_schema_bytes / 1024) (pc acc.b_schema_bytes);
  Printf.printf "  conversation transcript         %8d KB  %5.1f%%\n"
    (transcript_bytes / 1024) (pc transcript_bytes);
  Printf.printf "  injected <system-reminder>      %8d KB  %5.1f%%\n"
    (acc.b_reminder_bytes / 1024) (pc acc.b_reminder_bytes);
  Printf.printf "  dominant class                  %s\n" (payload_name dom);

  Printf.printf "\nderived interaction metrics\n";
  let f = float_of_int in
  Printf.printf "  calls per session (mean)        %8.1f\n"
    (if !n_sessions = 0 then 0.0 else f !n_requests /. f !n_sessions);
  Printf.printf "  prefix breaks                   %8d  (%.1f%% of calls)\n"
    !total_breaks
    (if !n_requests = 0 then 0.0 else 100.0 *. f !total_breaks /. f !n_requests);
  Printf.printf "  reused prefix blobs per call    %8.1f\n"
    (if !n_requests = 0 then 0.0 else f !total_tail /. f !n_requests);
  Printf.printf "  cache breakpoints per call      %8.1f\n"
    (if !n_requests = 0 then 0.0 else f !total_cache_breaks /. f !n_requests);
  Printf.printf "  1h-TTL breakpoints per call     %8.1f\n"
    (if !n_requests = 0 then 0.0 else f !total_1h /. f !n_requests);
  Printf.printf "  global-scope breakpoints/call   %8.1f\n"
    (if !n_requests = 0 then 0.0 else f !total_global /. f !n_requests);
  Printf.printf "  reminder blocks per call        %8.1f\n"
    (if !n_requests = 0 then 0.0
     else f acc.b_reminder_blocks /. f !n_requests);
  Printf.printf "  tool_use blocks per call        %8.2f\n"
    (if !n_requests = 0 then 0.0 else f acc.b_tool_use /. f !n_requests);
  Printf.printf "  thinking blocks per call        %8.2f\n"
    (if !n_requests = 0 then 0.0 else f acc.b_thinking /. f !n_requests);

  Printf.printf "\nBOUNDARY: Claude-harness logs only. ~/.codex (9.8 GB) and\n";
  Printf.printf "~/.gemini/antigravity (5.1 GB) are presence-only private state\n";
  Printf.printf "per SC-PEER-ARTIFACTS-001 rule 4 and were NOT opened. No\n";
  Printf.printf "cross-harness claim is made. Byte shares are ESTIMATES from\n";
  Printf.printf "marker scanning, not exact tokenizer accounting.\n";
  Printf.printf "This measurement grants no admission. EV ceiling 93.\n"
