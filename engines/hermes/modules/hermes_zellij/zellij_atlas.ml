type lifecycle =
  | Documented_only
  | Declared
  | Implemented
  | Tested
  | Live_verified
  | Unavailable_observed

type credit =
  | No_credit
  | Discovery_credit
  | Structural_credit
  | Functional_credit

type operation =
  | Install
  | Preflight
  | Observe_version
  | Render_kdl
  | Validate_kdl
  | Backup
  | Project
  | Install_command
  | List_sessions
  | Ensure
  | Attach
  | Observe
  | Verify
  | Status
  | Detect_drift
  | Tmux_non_interference
  | Removal_plan
  | Docs_audit

type row = {
  id : string;
  ontology_id : string;
  session : Zellij_intent.session option;
  operation : operation option;
  lifecycle : lifecycle;
  credit : credit;
  documentation_url : string option;
  description : string;
  implementation_paths : string list;
  test_paths : string list;
  residuals : string list;
}

let id value = value.id
let ontology_id value = value.ontology_id
let session value = value.session
let operation value = value.operation
let lifecycle value = value.lifecycle
let credit value = value.credit
let documentation_url value = value.documentation_url
let description value = value.description
let residuals value = value.residuals
let with_credit value credit = { value with credit }

let lifecycle_name = function
  | Documented_only -> "Documented_only"
  | Declared -> "Declared"
  | Implemented -> "Implemented"
  | Tested -> "Tested"
  | Live_verified -> "Live_verified"
  | Unavailable_observed -> "Unavailable_observed"

let credit_name = function
  | No_credit -> "No_credit"
  | Discovery_credit -> "Discovery_credit"
  | Structural_credit -> "Structural_credit"
  | Functional_credit -> "Functional_credit"

let operation_name = function
  | Install -> "install"
  | Preflight -> "preflight"
  | Observe_version -> "observe-version"
  | Render_kdl -> "render-kdl"
  | Validate_kdl -> "validate-kdl"
  | Backup -> "backup"
  | Project -> "project"
  | Install_command -> "install-command"
  | List_sessions -> "list-sessions"
  | Ensure -> "ensure"
  | Attach -> "attach"
  | Observe -> "observe"
  | Verify -> "verify"
  | Status -> "status"
  | Detect_drift -> "detect-drift"
  | Tmux_non_interference -> "tmux-non-interference"
  | Removal_plan -> "removal-plan"
  | Docs_audit -> "docs-audit"

let make ?session ?operation ?documentation_url ?(implementation_paths = [])
    ?(test_paths = []) ?(residuals = []) ~id ~ontology_id ~lifecycle ~credit
    ~description () =
  {
    id;
    ontology_id;
    session;
    operation;
    lifecycle;
    credit;
    documentation_url;
    description;
    implementation_paths;
    test_paths;
    residuals;
  }

let ontology capability = "harness-bionic.zellij." ^ capability

let general_rows =
  [
    ( Install,
      "controller",
      "Install Zellij from Cargo with its locked dependency graph" );
    ( Preflight,
      "controller",
      "Refuse before mutation when required resources are unmet" );
    (Observe_version, "runtime", "Observe the exact installed Zellij version");
    (Render_kdl, "projections", "Render KDL deterministically from typed intent");
    ( Validate_kdl,
      "contracts",
      "Validate owned KDL with native and owned checks" );
    ( Backup,
      "controller",
      "Preserve superseded user configuration before activation" );
    ( Project,
      "projections",
      "Project KDL, commands, documentation, JSON, and MBSE" );
    ( Install_command,
      "projections",
      "Install the OCaml launcher and exact command links" );
    ( List_sessions,
      "runtime",
      "List live session identities without formatting ambiguity" );
    ( Status,
      "receipts",
      "Classify declared, projected, observed, and current states" );
    (Detect_drift, "receipts", "Detect intent, projection, or runtime drift");
    ( Tmux_non_interference,
      "contracts",
      "Prove tmux state is unchanged by Zellij operations" );
    (Removal_plan, "controller", "Render a bounded reversible removal plan");
    ( Docs_audit,
      "projections",
      "Audit official documentation provenance and applicability" );
  ]
  |> List.map (fun (operation, node, description) ->
      make
        ~id:("zellij." ^ operation_name operation)
        ~ontology_id:(ontology node) ~operation ~lifecycle:Declared
        ~credit:Structural_credit ~description
        ~implementation_paths:[ "modules/hermes_zellij" ]
        ~test_paths:[ "modules/hermes_zellij/test_zellij_model.ml" ]
        ())

let session_rows =
  Zellij_intent.all_sessions
  |> List.concat_map (fun session ->
      let name = Zellij_intent.session_name session in
      [ Attach; Ensure; Observe; Verify ]
      |> List.map (fun operation ->
          make
            ~id:("zellij.session." ^ name ^ "." ^ operation_name operation)
            ~ontology_id:("harness-bionic.zellij." ^ name)
            ~session ~operation ~lifecycle:Implemented ~credit:Structural_credit
            ~description:
              (Printf.sprintf "%s the independent %s session"
                 (String.capitalize_ascii (operation_name operation))
                 name)
            ~implementation_paths:
              [
                "modules/hermes_zellij/zellij_intent.ml";
                "modules/hermes_zellij/zellij_algebra.ml";
              ]
            ~test_paths:[ "modules/hermes_zellij/test_zellij_model.ml" ]
            ()))

let documentation_specs =
  [
    ("introduction", "Introduction");
    ("installation", "Installation");
    ("integration", "Integration");
    ("faq", "FAQ");
    ("commands", "Commands");
    ("rebinding-keys", "Rebinding Keys");
    ("keybinding-presets", "Keybinding Presets");
    ("changing-modifiers", "Changing Modifiers");
    ("configuration", "Configuration");
    ("options", "Options");
    ("keybindings", "Keybindings");
    ("keybindings-modes", "Keybinding Modes");
    ("keybindings-binding", "Binding and Overriding Keys");
    ("keybindings-keys", "Keys");
    ("keybindings-possible-actions", "Possible Actions");
    ("keybindings-shared", "Shared Bindings");
    ("themes", "Themes");
    ("theme-list", "List of Themes");
    ("legacy-themes", "Legacy Themes");
    ("command-line-options", "CLI Configuration");
    ("migrating-yaml-config", "Migrating YAML Configuration");
    ("controlling-zellij-through-cli", "Controlling Zellij through the CLI");
    ("zellij-run-and-edit", "Zellij Run and Edit");
    ("cli-actions", "Zellij Action");
    ("zellij-plugin-and-pipe", "Zellij Plugin and Pipe");
    ("zellij-subscribe", "Zellij Subscribe");
    ("cli-recipes", "CLI Recipes and Scripting");
    ("programmatic-control", "Programmatic Control");
    ("layouts", "Layouts");
    ("creating-a-layout", "Creating a Layout");
    ("swap-layouts", "Swap Layouts");
    ("layouts-with-config", "Including Configuration in Layouts");
    ("layout-examples", "Layout Examples");
    ("migrating-yaml-layouts", "Migrating YAML Layouts");
    ("plugins", "Plugins");
    ("plugin-loading", "Loading Plugins");
    ("plugin-api", "Plugin API");
    ("plugin-api-events", "Plugin API Events");
    ("plugin-api-commands", "Plugin API Commands");
    ("plugin-api-types", "Plugin API Type Reference");
    ("plugin-api-permissions", "Plugin API Permissions");
    ("plugin-api-configuration", "Plugin API Configuration");
    ("plugin-api-file-system", "Plugin Filesystem Access");
    ("plugin-api-logging", "Plugin Logging");
    ("plugin-api-workers", "Plugin Workers");
    ("plugin-pipes", "Plugin Pipes");
    ("plugin-development", "Developing a Plugin");
    ("plugin-dev-env", "Plugin Development Environment");
    ("plugin-lifecycle", "Plugin Lifecycle");
    ("plugin-ui-rendering", "Plugin UI Rendering");
    ("plugin-upgrading", "Plugin Upgrading and Compatibility");
    ("plugin-aliases", "Plugin Aliases");
    ("tab-bar-alias", "Tab Bar Alias");
    ("status-bar-alias", "Status Bar Alias");
    ("strider-alias", "Strider Alias");
    ("compact-bar-alias", "Compact Bar Alias");
    ("session-manager-alias", "Session Manager Alias");
    ("welcome-screen-alias", "Welcome Screen Alias");
    ("filepicker-alias", "Filepicker Alias");
    ("plugin-examples", "Example Plugins");
    ("plugin-other-languages", "Plugins in Other Languages");
    ("session-resurrection", "Session Resurrection");
    ("web-client", "Web Client");
    ("compatibility", "Compatibility");
  ]

let documentation_pages =
  List.map
    (fun (slug, title) ->
      let documentation_url =
        "https://zellij.dev/documentation/" ^ slug ^ ".html"
      in
      make ~id:("zellij.docs." ^ slug) ~ontology_id:(ontology "projections")
        ~documentation_url ~lifecycle:Documented_only ~credit:No_credit
        ~description:title
        ~residuals:
          [ "applicability to installed version requires verification" ]
        ())
    documentation_specs

let rows = general_rows @ session_rows @ documentation_pages

let duplicates values =
  let sorted = List.sort String.compare values in
  let rec loop acc = function
    | left :: (right :: _ as tail) when left = right -> loop (left :: acc) tail
    | _ :: tail -> loop acc tail
    | [] -> List.rev acc
  in
  loop [] sorted

let validate_rows candidate =
  let errors = ref [] in
  let add message = errors := message :: !errors in
  duplicates (List.map (fun row -> row.id) candidate)
  |> List.iter (fun id -> add ("duplicate atlas id: " ^ id));
  List.iter
    (fun row ->
      if String.trim row.id = "" then add "blank atlas id";
      if String.trim row.description = "" then
        add ("blank description: " ^ row.id);
      if Option.is_none (Zellij_ontology.find row.ontology_id) then
        add ("unresolved ontology id: " ^ row.ontology_id);
      match row.documentation_url with
      | Some _ when row.lifecycle <> Documented_only ->
          add ("documentation row has non-documentation lifecycle: " ^ row.id)
      | Some _ when row.credit <> No_credit ->
          add ("documentation row leaks semantic credit: " ^ row.id)
      | None when row.lifecycle = Documented_only ->
          add ("documentation lifecycle lacks URL: " ^ row.id)
      | _ -> ())
    candidate;
  List.iter
    (fun session ->
      List.iter
        (fun operation ->
          if
            not
              (List.exists
                 (fun row ->
                   row.session = Some session && row.operation = Some operation)
                 candidate)
          then
            add
              (Printf.sprintf "missing %s row for %s" (operation_name operation)
                 (Zellij_intent.session_name session)))
        [ Attach; Ensure; Observe; Verify ])
    Zellij_intent.all_sessions;
  List.rev !errors

let validate () = validate_rows rows

let has_session_operation ~session ~operation =
  List.exists
    (fun row -> row.session = Some session && row.operation = Some operation)
    rows

let digest =
  rows
  |> List.map (fun row ->
      String.concat "|"
        [
          row.id;
          row.ontology_id;
          lifecycle_name row.lifecycle;
          credit_name row.credit;
          row.description;
        ])
  |> String.concat "\n" |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex
