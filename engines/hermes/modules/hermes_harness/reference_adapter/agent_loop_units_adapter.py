# Reference adapter: replay agent-loop slice units (prompt assembly, context
# references, compression markers, turn finalization).
#
# DECLARED EXCEPTION to the OCaml-only rule (see hermes_harness/ocaml_only_guard.ml).
# The thinnest possible driver for the measured system: each scenario names a
# frozen unit and this dispatches to it — prompt_builder frontmatter/steer/
# budget, context_references parse/quote, context_compressor skill markers,
# turn_finalizer/turn_summary predicates and formatters. It reads labeled
# cases on stdin, applies the frozen unit, and writes the observed output on
# stdout. It makes no parity decision and knows nothing about the OCaml
# candidate; normalization, comparison, digesting and storage all happen in
# OCaml. Imports are per-unit so a scenario only executes the module it
# measures; fd-level output discipline for the same reason as the other
# adapters.
#
# Invoked only by hermes_harness/reference_capture.ml.

import dataclasses
import json
import os
import sys
import time


def main() -> int:
    real_stdout = os.fdopen(os.dup(1), "w")
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    os.close(devnull)

    def emit(payload: dict) -> None:
        print(json.dumps(payload, sort_keys=True, default=str), file=real_stdout)
        real_stdout.flush()

    try:
        scenario = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as error:
        emit({"error": f"unreadable scenario: {error}"})
        return 2

    params = scenario.get("params", {})
    unit = params.get("unit", "")

    try:
        if unit == "frontmatter_strip":
            from agent.prompt_builder import _strip_yaml_frontmatter

            def run(case):
                return _strip_yaml_frontmatter(case["content"])
        elif unit == "steer_marker":
            from agent.prompt_builder import format_steer_marker

            def run(case):
                return format_steer_marker(case["text"])
        elif unit == "context_file_budget":
            from agent.prompt_builder import _dynamic_context_file_max_chars

            def run(case):
                return _dynamic_context_file_max_chars(case.get("context_length"))
        elif unit == "reference_parse":
            from agent.context_references import parse_context_references

            def run(case):
                return [dataclasses.asdict(r) for r in parse_context_references(case["message"])]
        elif unit == "reference_quote":
            from agent.context_references import format_reference_value

            def run(case):
                return format_reference_value(case["value"])
        elif unit == "skill_markers":
            from agent.context_compressor import (
                _extract_pruned_skill_names,
                _reinject_pruned_skill_markers,
                _skill_pruned_marker,
            )

            def run(case):
                op = case["op"]
                if op == "marker":
                    return _skill_pruned_marker(case["name"])
                if op == "extract":
                    return _extract_pruned_skill_names(case["text"])
                return _reinject_pruned_skill_markers(case["summary"], case["names"])
        elif unit == "pure_tail":
            from agent.turn_finalizer import _is_pure_tool_call_tail

            def run(case):
                return _is_pure_tool_call_tail(case["message"])
        elif unit == "scaffolding":
            from agent.turn_finalizer import _drop_verification_continuation_scaffolding

            def run(case):
                messages = list(case["messages"])
                _drop_verification_continuation_scaffolding(messages)
                return messages
        elif unit == "summary_format":
            from agent.turn_summary import _count_diff_lines, _pluralize, format_elapsed

            def run(case):
                op = case["op"]
                if op == "elapsed":
                    return format_elapsed(case["seconds"])
                if op == "diff":
                    return list(_count_diff_lines(case["text"]))
                return _pluralize(case["count"], case["noun"])
        elif unit == "sensitive_text":
            from agent.redact import redact_sensitive_text

            def run(case):
                return redact_sensitive_text(
                    case["text"],
                    force=True,
                    redact_url_credentials=case["redact_url_credentials"],
                )
        elif unit == "registry":
            from types import SimpleNamespace

            from tools.tool_search import (
                estimate_tokens_from_schemas,
                listing_token_budget,
                should_activate,
            )

            def run(case):
                op = case["op"]
                if op == "estimate":
                    return estimate_tokens_from_schemas(case["tool_defs"])
                if op == "activate":
                    # the frozen function reads only config.enabled; a duck-typed
                    # namespace avoids the config.yaml-reading loader
                    cfg = SimpleNamespace(enabled=case["enabled"])
                    return should_activate(cfg, case["deferrable_tokens"], None)
                cfg = SimpleNamespace(
                    threshold_pct=case["threshold_pct"],
                    listing_max_tokens=case["listing_max_tokens"],
                )
                return listing_token_budget(cfg, case.get("context_length"))
        elif unit == "destructive":
            from agent.tool_dispatch_helpers import _is_destructive_command

            def run(case):
                return _is_destructive_command(case["cmd"])
        elif unit == "approval_normalize":
            from tools.write_approval import _normalize_enabled

            def run(case):
                return _normalize_enabled(case.get("value"))
        elif unit == "patch_parse":
            from tools.patch_parser import parse_v4a_patch

            def run(case):
                operations, error = parse_v4a_patch(case["patch"])
                return {
                    "operations": [dataclasses.asdict(op) for op in operations],
                    "error": error,
                }
        elif unit == "result":
            from agent.tool_guardrails import canonical_tool_args, classify_tool_failure
            from agent.tool_result_classification import file_mutation_result_landed

            def run(case):
                op = case["op"]
                if op == "canonical":
                    return canonical_tool_args(case["args"])
                if op == "classify":
                    return list(classify_tool_failure(case["tool_name"], case.get("result")))
                return file_mutation_result_landed(case["tool_name"], case.get("result"))
        elif unit == "coding_context":
            from agent.coding_context import (
                _detect_profile_name,
                _edit_format_line,
                _model_family,
            )

            def run(case):
                op = case["op"]
                if op == "family":
                    return _model_family(case["model"])
                if op == "line":
                    return _edit_format_line(case["model"])
                # pure branches only: off / on / non-interactive platform
                return _detect_profile_name(case["mode"], case["platform"], ".")
        elif unit == "ancestor":
            from pathlib import Path

            from agent.subdirectory_hints import _is_ancestor_or_same

            def run(case):
                return _is_ancestor_or_same(Path(case["a"]), Path(case["b"]))
        elif unit == "breakdown":
            from agent.context_breakdown import (
                _bytes_to_tokens,
                _chars_to_tokens,
                _json_tokens,
                _split_tools,
            )

            def run(case):
                op = case["op"]
                if op == "chars":
                    return _chars_to_tokens(case["text"])
                if op == "bytes":
                    return _bytes_to_tokens(case.get("size"))
                if op == "json":
                    return _json_tokens(case["value"])
                builtin, mcp, subagent = _split_tools(case["tools"])
                return [len(builtin), len(mcp), len(subagent)]
        elif unit == "cwd_placeholder":
            from gateway.cwd_placeholder import resolve_placeholder_terminal_cwd

            def run(case):
                return resolve_placeholder_terminal_cwd(
                    configured_cwd=case["configured_cwd"],
                    terminal_backend=case["terminal_backend"],
                    messaging_cwd=case.get("messaging_cwd"),
                    docker_mount_cwd_to_workspace=case["docker_mount_cwd_to_workspace"],
                    home_fallback=case["home_fallback"],
                )
        elif unit == "manager":
            from agent.memory_manager import (
                build_memory_context_block,
                memory_provider_tools_enabled,
                normalize_tool_schema,
                sanitize_context,
            )

            def run(case):
                op = case["op"]
                if op == "normalize":
                    return normalize_tool_schema(case["schema"])
                if op == "enabled":
                    return memory_provider_tools_enabled(
                        case.get("enabled_toolsets"),
                        case.get("disabled_toolsets"),
                        memory_tool_present=case["memory_tool_present"],
                    )
                if op == "sanitize":
                    return sanitize_context(case["text"])
                return build_memory_context_block(case["text"])
        elif unit == "trivial":
            from agent.memory_provider import is_trivial_prompt

            def run(case):
                return is_trivial_prompt(case.get("text"))
        elif unit == "session_state":
            from hermes_state import _cwd_prefix_clause, _system_prompt_hash, workspace_key
            from hermes_state import _workspace_key_clause

            def run(case):
                op = case["op"]
                if op == "hash":
                    return _system_prompt_hash(case["text"])
                if op == "workspace_key":
                    row = {"git_repo_root": case.get("git_repo_root"), "cwd": case.get("cwd")}
                    return workspace_key(row)
                if op == "cwd_clause":
                    clause, params = _cwd_prefix_clause(case["cwd_prefix"])
                    return [clause, params]
                clause, params = _workspace_key_clause(case["key"])
                return [clause, params]
        elif unit == "portability":
            from hermes_state_portability import SessionPortabilityMixin as M

            def run(case):
                op = case["op"]
                value = case.get("value")
                try:
                    if op == "text_or_none":
                        return {"ok": True, "value": M._import_text_or_none(value, "value")}
                    if op == "json_object_or_none":
                        return {"ok": True, "value": M._import_json_object_or_none(value, "value")}
                    if op == "float_or_none":
                        return M._float_or_none(value)
                    if op == "int_or_none":
                        return {"ok": True, "value": M._import_int_or_none(value, "value")}
                    if op == "int_or_default":
                        return M._int_or_default(value, case["default"])
                    return M._reasoning_json_value(value)
                except ValueError as error:
                    return {"ok": False, "error": str(error)}
        elif unit == "discovery":
            from tools.skills_tool import (
                _collect_prerequisite_values,
                _get_required_environment_variables,
                _parse_tags,
                _skill_lookup_path_error,
                _sort_skills,
            )

            def run(case):
                op = case["op"]
                if op == "prereqs":
                    env_vars, commands = _collect_prerequisite_values(case["frontmatter"])
                    return {"env_vars": env_vars, "commands": commands}
                if op == "required_env":
                    return _get_required_environment_variables(case["frontmatter"])
                if op == "tags":
                    return _parse_tags(case.get("value"))
                if op == "sort":
                    return _sort_skills(case["skills"])
                return _skill_lookup_path_error(case["name"])
        elif unit == "bundles":
            from agent.skill_bundles import _slugify

            def run(case):
                return _slugify(case["name"])
        elif unit == "preprocessing":
            # sys is already imported at module level -- a local `import sys`
            # here would make Python treat it as local to the WHOLE main()
            # function (Python's function-scope binding rule), breaking the
            # `sys.stdin` read earlier in main() with UnboundLocalError. Bit
            # by this exact trap once already; not repeating it.
            import agent.skill_utils as _skill_utils_mod
            from agent.skill_preprocessing import substitute_template_vars
            from agent.skill_utils import (
                extract_skill_config_vars,
                extract_skill_description,
                is_skill_description_truncated_for_prompt,
                skill_matches_platform_list,
            )

            def run(case):
                op = case["op"]
                if op == "template":
                    return substitute_template_vars(
                        case["content"], case.get("skill_dir"), case.get("session_id")
                    )
                if op == "platform":
                    # skill_matches_platform_list reads sys.platform and
                    # agent.skill_utils.is_termux() internally -- pin both to
                    # the scenario's declared values so the reference is
                    # reproducible independent of the host running capture,
                    # then restore them unconditionally.
                    real_platform = sys.platform
                    real_is_termux = _skill_utils_mod.is_termux
                    sys.platform = case["current"]
                    _skill_utils_mod.is_termux = lambda: case["running_in_termux"]
                    try:
                        return skill_matches_platform_list(case.get("platforms"))
                    finally:
                        sys.platform = real_platform
                        _skill_utils_mod.is_termux = real_is_termux
                if op == "config_vars":
                    return extract_skill_config_vars(case["frontmatter"])
                return {
                    "description": extract_skill_description(case["frontmatter"]),
                    "truncated": is_skill_description_truncated_for_prompt(case["frontmatter"]),
                }
        elif unit == "sync":
            from tools.skills_sync import _is_tracked_user_modification
            from tools.skills_sync_client import (
                _merge_skill,
                _parse_bool,
                build_sync_manifest_bytes,
                canonical_json_bytes,
                parse_sync_manifest,
                wire_address,
            )

            def run(case):
                op = case["op"]
                if op == "canonical":
                    return canonical_json_bytes(case["obj"]).decode("utf-8")
                if op == "merge":
                    return _merge_skill(case.get("base"), case.get("ours"), case.get("theirs"))
                if op == "wire":
                    return wire_address(case["data"].encode("utf-8"))
                if op == "tracked":
                    return _is_tracked_user_modification(case["origin_hash"], case["user_hash"])
                if op == "bool":
                    return _parse_bool(case.get("value"))
                if op == "manifest_build":
                    return build_sync_manifest_bytes(case["skills"]).decode("utf-8")
                parsed = parse_sync_manifest(case["data"].encode("utf-8"))
                if parsed is None:
                    return None
                return [{"name": k, "enabled": v} for k, v in sorted(parsed.items())]
        elif unit == "provenance":
            from tools.skills_ast_audit import format_ast_report
            from tools.skills_guard import (
                Finding,
                ScanResult,
                _build_summary,
                _determine_verdict,
                _resolve_trust_level,
                format_scan_report,
                should_allow_install,
            )

            def run(case):
                op = case["op"]
                if op == "install":
                    stub = Finding(
                        pattern_id="p", severity="low", category="c", file="f", line=1,
                        match="m", description="d",
                    )
                    result = ScanResult(
                        skill_name="s", source="src", trust_level=case["trust_level"],
                        verdict=case["verdict"],
                        findings=[stub] * case["findings_count"],
                        scanned_at="", summary="", scan_provenance={},
                    )
                    allowed, reason = should_allow_install(result, force=case["force"])
                    return {"allowed": allowed, "reason": reason}
                if op == "verdict":
                    findings = [
                        Finding(pattern_id="p", severity=sev, category="c", file="f", line=1,
                                 match="m", description="d")
                        for sev in case["severities"]
                    ]
                    return _determine_verdict(findings)
                if op == "trust":
                    return _resolve_trust_level(case["source"])
                if op == "report":
                    findings = [
                        Finding(
                            pattern_id="p", severity=f["severity"], category=f["category"],
                            file=f["file"], line=f["line"], match=f["match"], description="d",
                        )
                        for f in case["findings"]
                    ]
                    result = ScanResult(
                        skill_name=case["skill_name"], source=case["source"],
                        trust_level=case["trust_level"], verdict=case["verdict"],
                        findings=findings, scanned_at="", summary="", scan_provenance={},
                    )
                    return format_scan_report(result)
                if op == "summary":
                    findings = [
                        Finding(pattern_id="p", severity="low", category=cat, file="f", line=1,
                                 match="m", description="d")
                        for cat in case["categories"]
                    ]
                    return _build_summary(
                        case["name"], "src", "community", case["verdict"], findings
                    )
                findings = [tuple(f) for f in case["findings"]]
                return format_ast_report(findings, case["skill_name"])
        elif unit == "repl":
            from tools.ansi_strip import strip_ansi
            from hermes_cli.console_engine import (
                _clean_summary,
                _format_sessions,
                _is_status_footer_rule,
                _strip_console_status_footer,
            )
            from hermes_cli.main import (
                _auto_provider_name,
                _coalesce_session_name_args,
                _dashboard_probe_host,
                _parse_dashboard_runtime,
            )

            def run(case):
                op = case["op"]
                if op == "strip_ansi":
                    return strip_ansi(case["text"])
                if op == "is_status_footer_rule":
                    return _is_status_footer_rule(case["line"])
                if op == "strip_console_status_footer":
                    return _strip_console_status_footer(case["text"])
                if op == "format_sessions":
                    return _format_sessions(case["sessions"])
                if op == "clean_summary":
                    return _clean_summary(case.get("text"))
                if op == "auto_provider_name":
                    return _auto_provider_name(case["base_url"])
                if op == "parse_dashboard_runtime":
                    result = _parse_dashboard_runtime(case["command"])
                    return None if result is None else list(result)
                if op == "dashboard_probe_host":
                    return _dashboard_probe_host(case.get("host"))
                return _coalesce_session_name_args(case["argv"])
        elif unit == "slash":
            from hermes_cli.commands import (
                _clamp_command_names,
                _nested_mapping,
                _sanitize_slack_name,
                _sanitize_telegram_name,
            )
            from hermes_cli.completion import _clean

            def run(case):
                op = case["op"]
                if op == "sanitize_telegram_name":
                    return _sanitize_telegram_name(case["raw"])
                if op == "sanitize_slack_name":
                    return _sanitize_slack_name(case["raw"])
                if op == "clamp_command_names":
                    entries = [tuple(e) for e in case["entries"]]
                    result = _clamp_command_names(entries, set(case["reserved"]))
                    return [list(e) for e in result]
                if op == "nested_mapping":
                    return _nested_mapping(case["root"], *case["path"])
                return _clean(case["text"], case.get("maxlen", 60))
        elif unit == "fuzzy":
            from hermes_cli.curses_ui import (
                _fuzzy_score,
                _is_boundary,
                _filter_indices,
                _move_filtered_cursor,
                _reconcile_cursor,
                _scroll_for_cursor,
                radio_item_plain,
            )

            def run(case):
                op = case["op"]
                if op == "is_boundary":
                    return _is_boundary(case["target"], case["index"])
                if op == "fuzzy_score":
                    return _fuzzy_score(case["item_label"], case["query"])
                if op == "filter_indices":
                    return _filter_indices(case["items"], case["query"])
                if op == "move_filtered_cursor":
                    return _move_filtered_cursor(
                        case["filtered"], case["cursor"], case["cursor_pos"], case["delta"]
                    )
                if op == "reconcile_cursor":
                    return list(_reconcile_cursor(case["filtered"], case["cursor"]))
                if op == "scroll_for_cursor":
                    return _scroll_for_cursor(
                        case["scroll_offset"], case["cursor_pos"], case["visible_rows"], case["total_rows"]
                    )
                item = case["item"]
                if isinstance(item, list):
                    item = [tuple(pair) for pair in item]
                return radio_item_plain(item)
        elif unit == "approval":
            from tools.approval import _has_allowlist_shell_operator
            from hermes_cli.approvals_suggest import (
                _unsafe_root_binary,
                derive_glob,
                is_unsafe_class,
                parse_apply_indices,
            )

            def run(case):
                op = case["op"]
                if op == "has_allowlist_shell_operator":
                    return _has_allowlist_shell_operator(case["command"])
                if op == "unsafe_root_binary":
                    return _unsafe_root_binary(case["token"])
                if op == "derive_glob":
                    return derive_glob(case["normalized"])
                if op == "is_unsafe_class":
                    return is_unsafe_class(case["description"])
                try:
                    result = parse_apply_indices(case["spec"], case["total"])
                    return {"ok": result}
                except ValueError as error:
                    return {"error": str(error)}
        elif unit == "bang":
            from hermes_cli.bang_shell import is_bang_command, parse_bang_command
            from hermes_cli.clipboard import _powershell_write_script, is_remote_shell_session

            def run(case):
                op = case["op"]
                if op == "is_bang_command":
                    return is_bang_command(case["text"])
                if op == "parse_bang_command":
                    return parse_bang_command(case["text"])
                if op == "is_remote_shell_session":
                    return is_remote_shell_session(case["env"])
                return _powershell_write_script(case["b64"])
        elif unit == "client":
            from tools.mcp_tool import (
                _normalize_mcp_input_schema,
                _normalize_name_filter,
                matches_name_filter,
                mcp_prefixed_tool_name,
            )
            from tools.mcp_schema_cache import config_fingerprint

            def run(case):
                op = case["op"]
                if op == "normalize_schema":
                    return _normalize_mcp_input_schema(case["schema"])
                if op == "fingerprint":
                    return config_fingerprint(case["config"])
                if op == "matches_filter":
                    patterns = _normalize_name_filter(case["patterns"], "test")
                    return matches_name_filter(case["tool_name"], patterns)
                return mcp_prefixed_tool_name(case["server_name"], case["tool_name"])
        elif unit == "oauth":
            from tools.mcp_oauth import (
                _safe_filename,
                apply_oauth_provider_defaults,
                humanize_oauth_registration_error,
            )
            from tools.mcp_oauth_manager import _same_endpoint

            def run(case):
                op = case["op"]
                if op == "humanize_error":
                    return humanize_oauth_registration_error(
                        case["server_name"], case["exc"], server_url=case.get("server_url")
                    )
                if op == "apply_defaults":
                    return apply_oauth_provider_defaults(
                        dict(case["cfg"]), server_name=case.get("server_name", ""),
                        server_url=case.get("server_url"),
                    )
                if op == "safe_filename":
                    return _safe_filename(case["name"])
                return _same_endpoint(case["a"], case["b"])
        elif unit == "config":
            from hermes_cli.mcp_config import _bearer_auth_headers, _env_key_for_server, _parse_env_assignments, _strip_bearer_prefix
            from hermes_cli.mcp_catalog import (
                AuthSpec,
                CatalogEntry,
                CatalogError,
                TransportSpec,
                _build_server_config,
                _expand_install_dir,
            )

            def run(case):
                op = case["op"]
                if op == "strip_bearer":
                    return _strip_bearer_prefix(case["token"])
                if op == "parse_env":
                    try:
                        return {"ok": _parse_env_assignments(case["raw_env"])}
                    except ValueError as error:
                        return {"error": str(error)}
                if op == "expand_install_dir":
                    try:
                        return {"ok": _expand_install_dir(case["value"], case.get("install_dir"))}
                    except CatalogError as error:
                        return {"error": str(error)}
                if op == "env_key":
                    return _env_key_for_server(case["name"])
                if op == "bearer_headers":
                    return _bearer_auth_headers(case["name"])
                transport = TransportSpec(
                    type=case["transport_type"], command=case.get("command"),
                    args=case.get("args") or [], url=case.get("url"),
                    env=case.get("env") or {},
                )
                auth = AuthSpec(type=case["auth_type"])
                entry = CatalogEntry(
                    name=case["name"], description="", source="", transport=transport, auth=auth,
                )
                return _build_server_config(entry, case.get("install_dir"))
        elif unit == "surface":
            from mcp_serve import _coerce_int, _extract_attachments, _extract_message_content, _row_to_index_entry, _ts_float

            def run(case):
                op = case["op"]
                if op == "extract_content":
                    return _extract_message_content(case["msg"])
                if op == "extract_attachments":
                    return _extract_attachments(case["msg"])
                if op == "row_to_entry":
                    real_tz = os.environ.get("TZ")
                    os.environ["TZ"] = "UTC"
                    time.tzset()
                    try:
                        return _row_to_index_entry(case["row"])
                    finally:
                        if real_tz is None:
                            os.environ.pop("TZ", None)
                        else:
                            os.environ["TZ"] = real_tz
                        time.tzset()
                if op == "ts_float":
                    real_tz = os.environ.get("TZ")
                    os.environ["TZ"] = "UTC"
                    time.tzset()
                    try:
                        return _ts_float(case["ts"])
                    finally:
                        if real_tz is None:
                            os.environ.pop("TZ", None)
                        else:
                            os.environ["TZ"] = real_tz
                        time.tzset()
                return _coerce_int(
                    case["value"], default=case["default"], minimum=case["minimum"], maximum=case["maximum"]
                )
        elif unit == "supervision":
            from hermes_cli.mcp_security import (
                _command_basename,
                is_mcp_server_entry_suspicious,
                validate_mcp_server_entry,
            )

            def run(case):
                op = case["op"]
                if op == "validate_entry":
                    return validate_mcp_server_entry(case["name"], case["entry"])
                if op == "command_basename":
                    return _command_basename(case["command"])
                return is_mcp_server_entry_suspicious(case["name"], case["entry"])
        elif unit == "lifecycle":
            import agent.subagent_lifecycle as _lifecycle_mod
            from agent.subagent_lifecycle import (
                SubagentHandle,
                SubagentLaunchRequest,
                SubagentLifecycleError,
                SubagentLifecycleService,
            )

            def run(case):
                op = case["op"]
                if op == "handle_from_dict":
                    try:
                        handle = SubagentHandle.from_dict(case["value"])
                        return {"ok": handle.to_dict()}
                    except SubagentLifecycleError as error:
                        return {"error": str(error)}
                if op == "validate_request":
                    request = SubagentLaunchRequest(
                        goal=case["goal"], context=case.get("context"), role=case.get("role", "leaf"),
                        allowed_toolsets=tuple(case.get("allowed_toolsets") or ()) or None,
                        blocked_tools=tuple(case.get("blocked_tools") or ()),
                        working_directory=case.get("working_directory"),
                        timeout_seconds=case.get("timeout_seconds"),
                        metadata=case.get("metadata") or {},
                    )

                    class _Parent:
                        enabled_toolsets = case.get("parent_enabled_toolsets")

                    real_toolsets = None
                    try:
                        import toolsets as _toolsets_mod

                        real_toolsets = dict(_toolsets_mod.TOOLSETS)
                        _toolsets_mod.TOOLSETS.clear()
                        _toolsets_mod.TOOLSETS.update({name: None for name in case.get("known_toolsets") or []})
                    except ImportError:
                        pass
                    try:
                        SubagentLifecycleService._validate_request(request, _Parent())
                        return {"ok": True}
                    except SubagentLifecycleError as error:
                        return {"error": str(error)}
                    finally:
                        if real_toolsets is not None:
                            _toolsets_mod.TOOLSETS.clear()
                            _toolsets_mod.TOOLSETS.update(real_toolsets)
                # op == "capability": pin _SECRET to a fixed, harness-declared
                # value so the HMAC is reproducible from outside the live
                # process (the frozen module generates it randomly at import).
                real_secret = _lifecycle_mod._SECRET
                _lifecycle_mod._SECRET = bytes.fromhex(case["secret_hex"])
                try:
                    return SubagentLifecycleService._capability(
                        case["subagent_id"], case.get("parent_session_id"), case["created_at"]
                    )
                finally:
                    _lifecycle_mod._SECRET = real_secret
        elif unit == "delegation":
            from tools.delegate_tool import (
                _build_child_system_prompt,
                _extract_output_tail,
                _looks_like_error_output,
                _normalize_role,
                _normalized_runtime_url,
                _stringify_tool_content,
                _strip_model_hidden_task_fields,
            )
            from agent.delegation_context import scrub_kanban_env

            def run(case):
                op = case["op"]
                if op == "child_prompt":
                    return _build_child_system_prompt(
                        case["goal"], case.get("context"), workspace_path=case.get("workspace_path"),
                        role=case.get("role", "leaf"), max_spawn_depth=case.get("max_spawn_depth", 2),
                        child_depth=case.get("child_depth", 1),
                    )
                if op == "stringify_content":
                    return _stringify_tool_content(case["content"])
                if op == "looks_like_error":
                    return _looks_like_error_output(case["content"])
                if op == "output_tail":
                    return _extract_output_tail(
                        case["result"], max_entries=case.get("max_entries", 12), max_chars=case.get("max_chars", 8000)
                    )
                if op == "scrub_env":
                    return scrub_kanban_env(case["env"])
                if op == "normalize_role":
                    return _normalize_role(case.get("role"))
                if op == "normalized_url":
                    return _normalized_runtime_url(case.get("value"))
                return _strip_model_hidden_task_fields(case["tasks"])
        elif unit == "async":
            from tools.async_delegation import _children_activity_from_token, _matches_session_selectors
            from tools.delegation_live_log import _one_line

            def run(case):
                op = case["op"]
                if op == "children_activity":
                    return _children_activity_from_token(case["token"], case["now"])
                if op == "one_line":
                    return _one_line(case["text"], case["limit"])
                result = _matches_session_selectors(
                    case["record"], session_key=case.get("session_key", ""),
                    origin_ui_session_id=case.get("origin_ui_session_id", ""),
                    parent_session_id=case.get("parent_session_id", ""),
                )
                return {"raw": result, "truthy": bool(result)}
        elif unit == "moa":
            from agent.moa_loop import (
                _degraded_notice,
                _failed_reference_labels,
                _is_failed_reference,
                _merge_slot_extra_body,
                _preset_temperature,
                _reference_messages,
                _render_tool_calls,
                _slot_label,
                _successful_references,
                _truncate_tool_result,
                peel_reference_guidance,
            )
            from agent.moa_trace import _sanitize_session_id
            from agent.message_content import flatten_message_text

            def run(case):
                op = case["op"]
                if op == "peel_guidance":
                    return peel_reference_guidance(case["messages"], case["guidance"])
                if op == "flatten_text":
                    return flatten_message_text(case["content"])
                if op == "reference_messages":
                    return _reference_messages(case["messages"])
                if op == "render_calls":
                    return _render_tool_calls(case.get("tool_calls"))
                if op == "truncate_result":
                    return _truncate_tool_result(case["text"], budget=case["budget"])
                if op == "is_failed":
                    return _is_failed_reference(case["text"])
                if op == "successful_refs":
                    return _successful_references([tuple(r) for r in case["reference_outputs"]])
                if op == "failed_labels":
                    return _failed_reference_labels([tuple(r) for r in case["reference_outputs"]])
                if op == "degraded_notice":
                    return _degraded_notice(case["failed_labels"], case["policy"])
                if op == "preset_temp":
                    return _preset_temperature(case["preset"], case["key"])
                if op == "slot_label":
                    return _slot_label(case["slot"])
                if op == "sanitize_session":
                    return _sanitize_session_id(case.get("session_id"))
                return _merge_slot_extra_body(case["slot_extra_body"], case["caller_extra_body"])
        elif unit == "kanban":
            from hermes_cli.kanban_swarm import _require_text, _swarm_context, parse_worker_arg
            from tools.kanban_tools import _normalize_profile, _ok, _parse_bool_arg

            def run(case):
                op = case["op"]
                if op == "parse_worker":
                    try:
                        spec = parse_worker_arg(case["raw"])
                        return {"ok": dataclasses.asdict(spec)}
                    except ValueError as error:
                        return {"error": str(error)}
                if op == "require_text":
                    try:
                        return {"ok": _require_text(case["value"], case["field_name"])}
                    except ValueError as error:
                        return {"error": str(error)}
                if op == "swarm_context":
                    return _swarm_context(case["root_id"], case["goal"])
                if op == "parse_bool":
                    value, error = _parse_bool_arg(case["args"], case["name"], default=case.get("default", False))
                    return {"value": value, "error": error}
                if op == "ok_envelope":
                    return _ok(**{k: v for k, v in case.get("fields", [])})
                return _normalize_profile(case["value"])
        else:
            emit({"error": f"unknown unit: {unit!r}"})
            return 2
    except Exception as error:  # noqa: BLE001 - the harness reports the reason
        emit({"error": f"reference import failed: {error!r}"})
        return 3

    try:
        results = {case["label"]: run(case) for case in params.get("cases", [])}
    except Exception as error:  # noqa: BLE001 - a reference failure is evidence too
        emit({"error": f"reference raised: {error!r}"})
        return 4

    emit({"trace": {"results": results}})
    return 0


if __name__ == "__main__":
    sys.exit(main())
