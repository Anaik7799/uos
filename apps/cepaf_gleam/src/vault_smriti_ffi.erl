%%% =============================================================================
%%% [C3I-SIL6] vault_smriti_ffi — Slice F (Pass-35) honest filesystem-guard variant.
%%% =============================================================================
%%% Stub-That-Lies guard ([zk-3346fc607a1ef9e6], RPN 729):
%%%
%%% Pass-24 shipped a flat `{error, <<"not_yet_wired">>}` placeholder.
%%% Pass-35 upgrades to a *more honest* token tree:
%%%
%%%   * `{error, <<"smriti_db_not_found">>}`   — DB file absent at expected path
%%%   * `{error, <<"smriti_db_not_readable">>}` — file exists but stat() fails
%%%   * `{error, <<"smriti_select_not_yet_wired">>}` — file present + readable,
%%%     but real SQL execution still pending (rusqlite/esqlite path).
%%%
%%% Why three tokens instead of one?
%%%   The supervisor's audit reconcile path needs to distinguish "no DB yet"
%%%   (cold-boot, perfectly normal) from "DB present but query path missing"
%%%   (deferred work, must surface in dashboards). Collapsing both into one
%%%   string defeats the alarm rules in `data_quality_scan` (SC-VAULT-008
%%%   audit append-only invariant relies on knowing whether the table even
%%%   exists yet).
%%%
%%% This module deliberately does NOT introduce a sqlite dep. That's a
%%% separate later pass (per Wave-4 dispatch instructions: "DO NOT add a
%%% new dep"). What it DOES do: reach for the canonical Smriti.db path,
%%% verify it exists, and refuse to lie either way.
%%%
%%% SC-ARCH-SPLIT-001: Long-term, real SQL must run in the planning_daemon
%%% Rust process and reach Gleam via Zenoh, not embed rusqlite in a NIF.
%%% =============================================================================

-module(vault_smriti_ffi).
-export([select_actual_policies/0, smriti_db_path/0]).

%% Canonical Smriti.db location, mirrored from CLAUDE.md §12 sa-plan-daemon notes.
%% Wrapped in a function so tests can override via a different path probe later.
smriti_db_path() ->
    <<"/home/an/dev/ver/c3i/data/kms/smriti.db">>.

%% select_actual_policies/0 — used by vault_audit_reconcile_io:fetch_actual_policies.
%% Returns a triple-state honest error per the Stub-That-Lies guard:
%%   1. {error, <<"smriti_db_not_found">>}        — file does not exist
%%   2. {error, <<"smriti_db_not_readable">>}     — exists but stat fails
%%   3. {error, <<"smriti_select_not_yet_wired">>} — exists, readable, no SQL yet
select_actual_policies() ->
    Path = binary_to_list(smriti_db_path()),
    case filelib:is_regular(Path) of
        false ->
            {error, <<"smriti_db_not_found">>};
        true ->
            case file:read_file_info(Path) of
                {error, _} ->
                    {error, <<"smriti_db_not_readable">>};
                {ok, _Info} ->
                    %% File exists and is statable. Real SQL still pending.
                    %% This token is the new lock-in trap upgrade target.
                    {error, <<"smriti_select_not_yet_wired">>}
            end
    end.
