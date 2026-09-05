(* skills units, reproduced faithfully from the frozen tools/skills_tool.py,
   agent/skill_commands.py, agent/skill_bundles.py, agent/skill_preprocessing.py,
   agent/skill_utils.py, tools/skills_sync.py, tools/skills_sync_client.py,
   tools/skills_hub.py, tools/skills_guard.py and tools/skills_ast_audit.py
   (each read completely before writing, via a parallel four-agent survey of
   the whole family; parity is measured by the skill.* scenarios, never
   assumed).

   Excluded, disclosed beside the scenarios or here:
     - parse_frontmatter (agent/skill_utils.py) -- full YAML 1.1 parsing
       (PyYAML SafeLoader semantics: bare yes/no/on/off type-folding, the
       blank-line-after-fence consumption quirk) is a disproportionate
       undertaking for one function; every OTHER skill_preprocessing
       candidate below takes an already-parsed frontmatter dict, so this
       gap does not block them. A future increment.
     - _scan_source (tools/skills_ast_audit.py) -- its entire behaviour is
       defined by Python's `ast.parse`, i.e. a full Python grammar; embedding
       or reimplementing that is out of scope for a unit port.
     - _decode_jwt_payload_unverified -- defined by PyJWT's decode semantics,
       not by anything in the frozen file itself.
     - skill_view, scan_file/scan_skill, the *_sh/*Source classes, and every
       function that reads a SKILL.md, resolves config.yaml, or does network
       I/O -- these are the impure resolution layers the pure cores below
       sit under.
     - skill_catalog (family slice 6): its anchors are directories of
       per-skill helper scripts, not an infrastructure module; confirmed
       (149 .py files checked) to have no unit-level candidate. *)

let lower = String.lowercase_ascii

let contains ~needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec at i = i + n <= h && (String.sub haystack i n = needle || at (i + 1)) in
  n = 0 || at 0

let starts_with prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

let ends_with suffix s =
  let sl = String.length suffix and n = String.length s in
  n >= sl && String.sub s (n - sl) sl = suffix

(* Python str.strip(chars): trim any character IN THE SET from both ends,
   not a literal substring -- this bit three separate functions below. *)
let strip_charset chars s =
  let is_in c = String.contains chars c in
  let n = String.length s in
  let i = ref 0 and j = ref (n - 1) in
  while !i < n && is_in s.[!i] do incr i done;
  while !j >= !i && is_in s.[!j] do decr j done;
  if !j < !i then "" else String.sub s !i (!j - !i + 1)

let strip s = strip_charset " \t\n\r\012\011" s

(* Python str() over the JSON leaf shapes these scenarios exercise. *)
let python_str = function
  | `String s -> s
  | `Bool true -> "True"
  | `Bool false -> "False"
  | `Null -> "None"
  | `Int n -> string_of_int n
  | other -> Yojson.Safe.to_string other

let field name = function `Assoc f -> List.assoc_opt name f | _ -> None
let str_field name obj = match field name obj with Some (`String s) -> Some s | _ -> None

(* Python truthiness on a JSON value -- the falsy set is None/False/0/""/[]/{}. *)
let truthy = function
  | `Null | `Bool false | `String "" | `List [] | `Assoc [] | `Int 0 -> false
  | `Float f -> f <> 0.0
  | _ -> true

(* ---- shared: canonical (compact, sorted) JSON, ensure_ascii=false ----
   Reused by skill_sync's wire-protocol functions; a local copy rather than a
   cross-module dependency, matching this session's established convention
   (memory_units.ml duplicates json_default_separators for the same reason). *)
let json_compact_sorted (value : Yojson.Safe.t) : string =
  let rec go (value : Yojson.Safe.t) : string =
    match value with
    | `Null -> "null"
    | `Bool b -> if b then "true" else "false"
    | `Int n -> string_of_int n
    | `Intlit s -> s
    | `Float f -> Yojson.Safe.to_string (`Float f)
    | `String s ->
        let b = Buffer.create (String.length s + 2) in
        Buffer.add_char b '"';
        String.iter
          (fun c ->
            match c with
            | '"' -> Buffer.add_string b "\\\""
            | '\\' -> Buffer.add_string b "\\\\"
            | '\n' -> Buffer.add_string b "\\n"
            | '\t' -> Buffer.add_string b "\\t"
            | '\r' -> Buffer.add_string b "\\r"
            | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
            | c -> Buffer.add_char b c)
          s;
        Buffer.add_char b '"';
        Buffer.contents b
    | `List items -> "[" ^ String.concat "," (List.map go items) ^ "]"
    | `Assoc fields ->
        let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) fields in
        "{" ^ String.concat "," (List.map (fun (k, v) -> go (`String k) ^ ":" ^ go v) sorted) ^ "}"
  in
  go value

(* =========================================================================
   skill_discovery (tools/skills_tool.py)
   ========================================================================= *)

let normalize_prerequisite_values value =
  if not (truthy value) then []
  else
    let items = match value with `String s -> [ `String s ] | `List l -> l | v -> [ v ] in
    List.filter_map
      (fun item ->
        let s = python_str item in
        if strip s <> "" then Some s else None)
      items

let collect_prerequisite_values frontmatter =
  match field "prerequisites" frontmatter with
  | Some (`Assoc _ as prereqs) ->
      ( normalize_prerequisite_values (Option.value (field "env_vars" prereqs) ~default:`Null),
        normalize_prerequisite_values (Option.value (field "commands" prereqs) ~default:`Null) )
  | _ -> ([], [])

type setup_metadata = { help : string option; collect_secrets : Yojson.Safe.t list }

let normalize_setup_metadata frontmatter =
  match field "setup" frontmatter with
  | Some (`Assoc _ as setup) ->
      let help =
        match str_field "help" setup with
        | Some h when strip h <> "" -> Some (strip h)
        | _ -> None
      in
      let raw =
        match field "collect_secrets" setup with
        | Some (`Assoc _ as one) -> [ one ]
        | Some (`List l) -> l
        | _ -> []
      in
      let collect_secrets =
        List.filter_map
          (fun item ->
            match item with
            | `Assoc _ ->
                let env_var =
                  strip (match str_field "env_var" item with Some s -> s | None -> "")
                in
                if env_var = "" then None
                else
                  let prompt =
                    strip
                      (match str_field "prompt" item with
                       | Some s when s <> "" -> s
                       | _ -> "Enter value for " ^ env_var)
                  in
                  let provider_url =
                    strip
                      (match (str_field "provider_url" item, str_field "url" item) with
                       | Some s, _ when s <> "" -> s
                       | _, Some s when s <> "" -> s
                       | _ -> "")
                  in
                  let secret =
                    match field "secret" item with Some v -> truthy v | None -> true
                  in
                  let entry =
                    [ ("env_var", `String env_var); ("prompt", `String prompt);
                      ("secret", `Bool secret) ]
                    @ if provider_url <> "" then [ ("provider_url", `String provider_url) ] else []
                  in
                  Some (`Assoc entry)
            | _ -> None)
          raw
      in
      { help; collect_secrets }
  | _ -> { help = None; collect_secrets = [] }

let is_env_var_name s =
  let n = String.length s in
  let is_alpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' in
  let is_alnum c = is_alpha c || (c >= '0' && c <= '9') in
  n > 0 && is_alpha s.[0] && (let rec go i = i >= n || (is_alnum s.[i] && go (i + 1)) in go 1)

let get_required_environment_variables ~frontmatter ~legacy_env_vars =
  let setup = normalize_setup_metadata frontmatter in
  let required_raw =
    match field "required_environment_variables" frontmatter with
    | Some (`Assoc _ as one) -> [ one ]
    | Some (`List l) -> l
    | _ -> []
  in
  let seen = Hashtbl.create 8 in
  let required = ref [] in
  let append_required entry =
    let env_name =
      strip
        (match (str_field "name" entry, str_field "env_var" entry) with
         | Some s, _ when s <> "" -> s
         | _, Some s when s <> "" -> s
         | _ -> "")
    in
    if env_name = "" || Hashtbl.mem seen env_name then ()
    else if not (is_env_var_name env_name) then ()
    else begin
      let prompt =
        strip
          (match str_field "prompt" entry with
           | Some s when s <> "" -> s
           | _ -> "Enter value for " ^ env_name)
      in
      let base = [ ("name", `String env_name); ("prompt", `String prompt) ] in
      let help_text =
        match
          ( str_field "help" entry, str_field "provider_url" entry, str_field "url" entry,
            setup.help )
        with
        | Some s, _, _, _ when s <> "" -> Some s
        | _, Some s, _, _ when s <> "" -> Some s
        | _, _, Some s, _ when s <> "" -> Some s
        | _, _, _, Some s -> Some s
        | _ -> None
      in
      let base = base @ (match help_text with Some h -> [ ("help", `String (strip h)) ] | None -> []) in
      let required_for =
        match str_field "required_for" entry with Some s when strip s <> "" -> Some (strip s) | _ -> None
      in
      let base = base @ (match required_for with Some r -> [ ("required_for", `String r) ] | None -> []) in
      let base =
        base @ (if (match field "optional" entry with Some v -> truthy v | None -> false)
                then [ ("optional", `Bool true) ] else [])
      in
      Hashtbl.add seen env_name ();
      required := `Assoc base :: !required
    end
  in
  List.iter
    (fun item ->
      match item with
      | `String s -> append_required (`Assoc [ ("name", `String s) ])
      | `Assoc _ -> append_required item
      | _ -> ())
    required_raw;
  List.iter
    (fun secret ->
      let provider_url = match str_field "provider_url" secret with Some s -> s | None -> "" in
      append_required
        (`Assoc
          [ ("name", Option.value (field "env_var" secret) ~default:`Null);
            ("prompt", Option.value (field "prompt" secret) ~default:`Null);
            ("help",
             `String (if provider_url <> "" then provider_url else Option.value setup.help ~default:"")) ]))
    setup.collect_secrets;
  let legacy =
    match legacy_env_vars with Some l -> l | None -> fst (collect_prerequisite_values frontmatter)
  in
  List.iter (fun env_var -> append_required (`Assoc [ ("name", `String env_var) ])) legacy;
  List.rev !required

let parse_tags = function
  | value when not (truthy value) -> []
  | `List items ->
      List.filter_map
        (fun t -> if truthy t then Some (strip (python_str t)) else None)
        items
  | value ->
      let s = strip (python_str value) in
      let s = if starts_with "[" s && ends_with "]" s then String.sub s 1 (String.length s - 2) else s in
      String.split_on_char ',' s
      |> List.filter_map (fun part ->
             let part = strip part in
             if part = "" then None else Some (strip_charset "\"'" part))

let sort_skills skills =
  List.stable_sort
    (fun a b ->
      let cat s = match str_field "category" s with Some c -> c | None -> "" in
      let name s = match str_field "name" s with Some n -> n | None -> "" in
      match compare (cat a) (cat b) with 0 -> compare (name a) (name b) | c -> c)
    skills

(* has_traversal_component (tools/path_security.py): any POSIX path
   component equal to "..". *)
let has_traversal_component path =
  String.split_on_char '/' path |> List.exists (fun part -> part = "..")

(* _skill_lookup_path_error, scoped: POSIX-absolute (leading /),
   Windows-drive-absolute (`C:\...`/`C:/...`), Windows-UNC-absolute
   (`\\server\...`/`//server/...`), and Windows-drive-relative (`C:foo`,
   caught by PureWindowsPath(...).drive being truthy even though
   .is_absolute() is false) all reject with the same message -- the frozen
   OR-chain never distinguishes them in its output, so this candidate
   doesn't need to either. Deep pathlib edge cases (mixed separators inside
   a UNC share name, etc.) are out of the tested domain. *)
let skill_lookup_path_error name =
  let candidate = strip name in
  let n = String.length candidate in
  let is_windows_drive_prefix =
    n >= 2
    && ((candidate.[0] >= 'A' && candidate.[0] <= 'Z') || (candidate.[0] >= 'a' && candidate.[0] <= 'z'))
    && candidate.[1] = ':'
  in
  let is_windows_absolute =
    (is_windows_drive_prefix && n >= 3 && (candidate.[2] = '\\' || candidate.[2] = '/'))
    || ((starts_with "\\\\" candidate || starts_with "//" candidate) && n > 2)
  in
  if starts_with "/" candidate || is_windows_absolute || is_windows_drive_prefix then
    Some "Skill name must be a relative path within the skills directory."
  else if has_traversal_component candidate then
    Some "Skill name cannot contain '..' path traversal components."
  else None

(* =========================================================================
   skill_bundles (agent/skill_bundles.py)
   ========================================================================= *)

let is_bundle_valid_char c =
  (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '-'

let slugify name =
  let step1 =
    String.map (fun c -> if c = ' ' || c = '_' then '-' else c) (lower name)
  in
  let step2 =
    let b = Buffer.create (String.length step1) in
    String.iter (fun c -> if is_bundle_valid_char c then Buffer.add_char b c) step1;
    Buffer.contents b
  in
  let b = Buffer.create (String.length step2) in
  let n = String.length step2 in
  let i = ref 0 in
  while !i < n do
    if step2.[!i] = '-' then begin
      Buffer.add_char b '-';
      while !i < n && step2.[!i] = '-' do incr i done
    end
    else begin
      Buffer.add_char b step2.[!i];
      incr i
    end
  done;
  strip_charset "-" (Buffer.contents b)

(* =========================================================================
   skill_preprocessing (agent/skill_preprocessing.py, agent/skill_utils.py)
   ========================================================================= *)

(* substitute_template_vars: ${HERMES_SKILL_DIR}/${HERMES_SESSION_ID}
   substitution. skill_dir/session_id model "if skill_dir"/"and session_id"
   Python truthiness -- None or an empty string both leave the token
   unresolved (kept literal). *)
let substitute_template_vars ~content ~skill_dir ~session_id =
  if content = "" then content
  else begin
    let resolve token =
      match token with
      | "HERMES_SKILL_DIR" -> (
          match skill_dir with Some s when s <> "" -> Some s | _ -> None)
      | "HERMES_SESSION_ID" -> (
          match session_id with Some s when s <> "" -> Some s | _ -> None)
      | _ -> None
    in
    let n = String.length content in
    let buffer = Buffer.create n in
    let i = ref 0 in
    while !i < n do
      if starts_with "${" (String.sub content !i (min 2 (n - !i))) then begin
        let close =
          let rec find j = if j >= n then None else if content.[j] = '}' then Some j else find (j + 1) in
          find (!i + 2)
        in
        match close with
        | Some close_at ->
            let token = String.sub content (!i + 2) (close_at - !i - 2) in
            (match resolve token with
             | Some value ->
                 Buffer.add_string buffer value;
                 i := close_at + 1
             | None ->
                 Buffer.add_string buffer (String.sub content !i (close_at - !i + 1));
                 i := close_at + 1)
        | None ->
            Buffer.add_char buffer content.[!i];
            incr i
      end
      else begin
        Buffer.add_char buffer content.[!i];
        incr i
      end
    done;
    Buffer.contents buffer
  end

let platform_map = [ ("macos", "darwin"); ("linux", "linux"); ("windows", "win32") ]

(* skill_matches_platform_list, parameterized on the environment (current
   platform string, termux flag) rather than reading sys.platform/is_termux()
   live -- the frozen function reads them internally, but a differential
   scenario needs a reproducible environment, not whatever host happens to
   run the capture. The adapter pins the SAME two values via monkeypatch
   before calling the frozen function, so both sides see identical inputs. *)
let skill_matches_platform_list ~current ~running_in_termux platforms =
  if not (truthy platforms) then true
  else
    let items = match platforms with `List l -> l | v -> [ v ] in
    List.exists
      (fun platform ->
        let normalized = lower (strip (python_str platform)) in
        let mapped = Option.value (List.assoc_opt normalized platform_map) ~default:normalized in
        starts_with mapped current
        || (running_in_termux && mapped = "linux")
        || (running_in_termux && (mapped = "termux" || mapped = "android")))
      items

let skill_matches_platform ~current ~running_in_termux frontmatter =
  skill_matches_platform_list ~current ~running_in_termux
    (Option.value (field "platforms" frontmatter) ~default:`Null)

let extract_skill_config_vars frontmatter =
  match field "metadata" frontmatter with
  | Some (`Assoc _ as metadata) -> (
      match field "hermes" metadata with
      | Some (`Assoc _ as hermes) -> (
          match field "config" hermes with
          | Some raw when truthy raw -> (
              let items = match raw with `Assoc _ -> [ raw ] | `List l -> l | _ -> [] in
              match raw with
              | `Assoc _ | `List _ ->
                  let seen = Hashtbl.create 8 in
                  List.filter_map
                    (fun item ->
                      match item with
                      | `Assoc _ ->
                          let key = strip (match str_field "key" item with Some s -> s | None -> "") in
                          if key = "" || Hashtbl.mem seen key then None
                          else
                            let desc =
                              strip (match str_field "description" item with Some s -> s | None -> "")
                            in
                            if desc = "" then None
                            else begin
                              Hashtbl.add seen key ();
                              let prompt =
                                match str_field "prompt" item with
                                | Some p when strip p <> "" -> strip p
                                | _ -> desc
                              in
                              let base =
                                [ ("key", `String key); ("description", `String desc) ]
                              in
                              let base =
                                match field "default" item with
                                | Some `Null | None -> base
                                | Some d -> base @ [ ("default", d) ]
                              in
                              Some (`Assoc (base @ [ ("prompt", `String prompt) ]))
                            end
                      | _ -> None)
                    items
              | _ -> [])
          | _ -> [])
      | _ -> [])
  | _ -> []

let skill_prompt_desc_limit = 60

let normalize_skill_description frontmatter =
  match field "description" frontmatter with
  | Some raw when truthy raw -> strip_charset "'\"" (strip (python_str raw))
  | _ -> ""

let extract_skill_description frontmatter =
  let desc = normalize_skill_description frontmatter in
  if desc = "" then ""
  else if String.length desc > skill_prompt_desc_limit then
    String.sub desc 0 (skill_prompt_desc_limit - 3) ^ "..."
  else desc

let is_skill_description_truncated_for_prompt frontmatter =
  String.length (normalize_skill_description frontmatter) > skill_prompt_desc_limit

(* =========================================================================
   skill_sync (tools/skills_sync.py, tools/skills_sync_client.py)
   ========================================================================= *)

let canonical_json_bytes obj = json_compact_sorted obj

let sync_manifest_type = "sync-manifest"
let sync_manifest_version = 1

let build_sync_manifest_bytes skills =
  let sorted = List.sort (fun (a, _) (b, _) -> String.compare a b) skills in
  canonical_json_bytes
    (`Assoc
      [ ("type", `String sync_manifest_type); ("version", `Int sync_manifest_version);
        ("skills",
         `List (List.map (fun (name, enabled) -> `Assoc [ ("name", `String name); ("enabled", `Bool enabled) ]) sorted))
      ])

let parse_sync_manifest data =
  match (try Some (Yojson.Safe.from_string data) with _ -> None) with
  | None -> None
  | Some (`Assoc _ as value) -> (
      if field "type" value <> Some (`String sync_manifest_type) then None
      else if field "version" value <> Some (`Int sync_manifest_version) then None
      else
        match field "skills" value with
        | Some (`List raw_skills) ->
            let rec go acc = function
              | [] -> Some (List.rev acc)
              | (`Assoc _ as raw) :: rest -> (
                  match (str_field "name" raw, field "enabled" raw) with
                  | Some name, Some (`Bool enabled) when name <> "" -> go ((name, enabled) :: acc) rest
                  | _ -> None)
              | _ :: _ -> None
            in
            go [] raw_skills
        | _ -> None)
  | Some _ -> None

let merge_skill ~base ~ours ~theirs =
  if ours = theirs then (if ours <> None then "either" else "none")
  else
    let ours_changed = ours <> base and theirs_changed = theirs <> base in
    if ours_changed && not theirs_changed then "ours"
    else if theirs_changed && not ours_changed then "theirs"
    else "overlap"

let wire_address data = "sha256:" ^ Memory_units.system_prompt_hash data

let is_tracked_user_modification ~origin_hash ~user_hash =
  origin_hash <> "" && user_hash <> origin_hash

let parse_bool_true = [ "1"; "true"; "yes"; "on" ]
let parse_bool_false = [ "0"; "false"; "no"; "off"; "" ]

let parse_bool = function
  | `Bool b -> Some b
  | `Null -> None
  | value ->
      let s = lower (strip (python_str value)) in
      if List.mem s parse_bool_true then Some true
      else if List.mem s parse_bool_false then Some false
      else None

(* =========================================================================
   skill_provenance (tools/skills_guard.py, tools/skills_ast_audit.py)
   ========================================================================= *)

let install_policy =
  [ ("builtin", ("allow", "allow", "allow")); ("trusted", ("allow", "allow", "block"));
    ("community", ("allow", "block", "block")); ("agent-created", ("allow", "allow", "ask")) ]

let verdict_index = function "safe" -> 0 | "caution" -> 1 | _ -> 2

(* should_allow_install: tri-state (allow / needs-confirmation / block), not
   a plain bool -- the frozen "ask" branch returns None. Findings only
   participate via their COUNT (the message text), never their content. *)
let should_allow_install ~trust_level ~verdict ~findings_count ~force =
  let allow, caution, dangerous =
    Option.value (List.assoc_opt trust_level install_policy)
      ~default:(let _, c, d = List.assoc "community" install_policy in ("allow", c, d))
  in
  let policy = [| allow; caution; dangerous |] in
  let decision = policy.(verdict_index verdict) in
  if decision = "allow" then
    (`Allowed, Printf.sprintf "Allowed (%s source, %s verdict)" trust_level verdict)
  else if force && not (verdict = "dangerous" && (trust_level = "community" || trust_level = "trusted"))
  then
    (`Allowed, Printf.sprintf "Force-installed despite %s verdict (%d findings)" verdict findings_count)
  else if decision = "ask" then
    ( `NeedsConfirmation,
      Printf.sprintf "Requires confirmation (%s source + %s verdict, %d findings)" trust_level verdict
        findings_count )
  else if verdict = "dangerous" && (trust_level = "community" || trust_level = "trusted") then
    ( `Blocked,
      Printf.sprintf
        "Blocked (%s source + dangerous verdict, %d findings). --force does not override a dangerous \
         verdict."
        trust_level findings_count )
  else
    ( `Blocked,
      Printf.sprintf "Blocked (%s source + %s verdict, %d findings). Use --force to override." trust_level
        verdict findings_count )

let determine_verdict severities =
  if severities = [] then "safe"
  else if List.mem "critical" severities then "dangerous"
  else if List.mem "high" severities then "caution"
  else "safe"

let trusted_repos = [ "openai/skills"; "anthropics/skills"; "huggingface/skills"; "NVIDIA/skills" ]
let repo_prefix_aliases = [ "skills-sh/"; "skills.sh/"; "skils-sh/"; "skils.sh/" ]

let resolve_trust_level source =
  let normalized =
    match List.find_opt (fun p -> starts_with p source) repo_prefix_aliases with
    | Some p -> String.sub source (String.length p) (String.length source - String.length p)
    | None -> source
  in
  if normalized = "agent-created" then "agent-created"
  else if normalized = "official" then "builtin"
  else if
    List.exists
      (fun trusted -> normalized = trusted || starts_with (trusted ^ "/") normalized)
      trusted_repos
  then "trusted"
  else "community"

let severity_order = function "critical" -> 0 | "high" -> 1 | "medium" -> 2 | _ -> 3

(* format_scan_report needs a STABLE sort on severity -- ties (findings of
   equal severity) must keep their original relative order, exactly the
   OCaml-specific trap the survey flagged: List.stable_sort, never
   List.sort. *)
let format_scan_report ~skill_name ~source ~trust_level ~verdict ~findings ~force =
  let get_str f name = match str_field name f with Some s -> s | None -> "" in
  let get_int f name = match field name f with Some (`Int n) -> n | _ -> 0 in
  let buffer = Buffer.create 256 in
  Printf.bprintf buffer "Scan: %s (%s/%s)  Verdict: %s\n" skill_name source trust_level
    (String.uppercase_ascii verdict);
  if findings <> [] then begin
    let sorted =
      List.stable_sort
        (fun a b -> compare (severity_order (get_str a "severity")) (severity_order (get_str b "severity")))
        findings
    in
    List.iter
      (fun f ->
        let sev = String.uppercase_ascii (get_str f "severity") in
        let sev_pad = sev ^ String.make (max 0 (8 - String.length sev)) ' ' in
        let cat = get_str f "category" in
        let cat_pad = cat ^ String.make (max 0 (14 - String.length cat)) ' ' in
        let loc = Printf.sprintf "%s:%d" (get_str f "file") (get_int f "line") in
        let loc_pad = loc ^ String.make (max 0 (30 - String.length loc)) ' ' in
        let m = get_str f "match" in
        let m = if String.length m > 60 then String.sub m 0 60 else m in
        Printf.bprintf buffer "  %s %s %s \"%s\"\n" sev_pad cat_pad loc_pad m)
      sorted;
    Buffer.add_char buffer '\n'
  end;
  let allowed, reason =
    should_allow_install ~trust_level ~verdict ~findings_count:(List.length findings) ~force
  in
  let status = match allowed with `Allowed -> "ALLOWED" | `NeedsConfirmation -> "NEEDS CONFIRMATION" | `Blocked -> "BLOCKED" in
  Printf.bprintf buffer "Decision: %s — %s" status reason;
  Buffer.contents buffer

let build_summary ~name ~verdict ~categories =
  if categories = [] then Printf.sprintf "%s: clean scan, no threats detected" name
  else
    let unique_sorted = List.sort_uniq compare categories in
    Printf.sprintf "%s: %s — %d finding(s) in %s" name verdict (List.length categories)
      (String.concat ", " unique_sorted)

(* format_ast_report: Finding = (file, line, pattern_id, description),
   sorted as a full 4-tuple -- every field participates, so ties require
   literally identical tuples and sort-stability is structurally moot here
   (unlike format_scan_report above). *)
let format_ast_report ~skill_name findings =
  let header = if skill_name <> "" then "AST deep scan: " ^ skill_name else "AST deep scan" in
  if findings = [] then header ^ "\n  No dynamic import/access patterns detected."
  else begin
    let sorted =
      List.sort
        (fun (f1, l1, p1, d1) (f2, l2, p2, d2) -> compare (f1, l1, p1, d1) (f2, l2, p2, d2))
        findings
    in
    let buffer = Buffer.create 256 in
    Buffer.add_string buffer header;
    Buffer.add_char buffer '\n';
    Printf.bprintf buffer "  %d finding(s):\n" (List.length findings);
    let current = ref None in
    List.iter
      (fun (f, line, pid, desc) ->
        if !current <> Some f then begin
          current := Some f;
          Printf.bprintf buffer "  %s\n" f
        end;
        Printf.bprintf buffer "    L%d  %s  — %s\n" line pid desc)
      sorted;
    Buffer.add_string buffer "\n  Note: diagnostic hints for human review, not security verdicts.";
    Buffer.contents buffer
  end
