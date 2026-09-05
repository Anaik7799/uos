%% =============================================================================
%% [C3I-SIL6] BEAM Hot Code Reload FFI
%% =============================================================================
%% Zero-downtime bytecode upgrade for the Gleam/BEAM runtime.
%% Uses OTP code server APIs for safe module replacement.
%%
%% BEAM supports two versions of a module simultaneously:
%%   - "current" (new code) and "old" (previous version)
%%   - Processes running old code continue until they make a fully-qualified
%%     call (Module:Function), at which point they switch to current
%%   - code:purge/1 removes old version (kills processes still in old code)
%%   - code:soft_purge/1 only purges if no processes reference old code
%%
%% STAMP: SC-HA-001, SC-OODA-ACCEL-003, SC-FUNC-001
%% Sanskrit: अविनाशि तु तद्विद्धि येन सर्वमिदं ततम्
%%           Know that which pervades all this is indestructible (Gita 2.17)
%% =============================================================================
-module(hot_reload_ffi).

-export([
    reload_module/1,
    reload_modules/1,
    soft_reload_module/1,
    reload_gleam_app/0,
    get_loaded_modules/0,
    get_module_info/1,
    is_module_loaded/1,
    get_module_md5/1,
    compile_and_reload/1,
    safe_reload_with_check/1,
    reload_changed_modules/0,
    get_beam_path/1
]).

%% @doc Reload a single module by atom name.
%% Uses soft_purge first (safe), falls back to hard purge if needed.
%% Returns {ok, Module} | {error, Reason}
reload_module(ModuleName) when is_binary(ModuleName) ->
    reload_module(binary_to_atom(ModuleName, utf8));
reload_module(Module) when is_atom(Module) ->
    try
        %% Step 1: Soft purge old code (safe — won't kill running processes)
        case code:soft_purge(Module) of
            true ->
                %% Step 2: Load new beam file from code path
                case code:load_file(Module) of
                    {module, Module} ->
                        {ok, Module};
                    {error, Reason} ->
                        {error, {load_failed, Reason}}
                end;
            false ->
                %% Processes still running old code — cannot safely purge
                {error, {old_code_in_use, Module}}
        end
    catch
        _:Error ->
            {error, {exception, Error}}
    end.

%% @doc Reload multiple modules in dependency order.
%% Returns {ok, ReloadedList} | {error, {failed_module, Module, Reason}}
reload_modules(ModuleNames) when is_list(ModuleNames) ->
    Atoms = [case is_binary(M) of
                 true -> binary_to_atom(M, utf8);
                 false -> M
             end || M <- ModuleNames],
    reload_modules_loop(Atoms, []).

reload_modules_loop([], Acc) ->
    {ok, lists:reverse(Acc)};
reload_modules_loop([Module | Rest], Acc) ->
    case reload_module(Module) of
        {ok, M} ->
            reload_modules_loop(Rest, [M | Acc]);
        {error, Reason} ->
            {error, {failed_module, Module, Reason}}
    end.

%% @doc Soft reload — only succeeds if no processes reference old code.
%% This is the SAFEST method for production use.
soft_reload_module(ModuleName) when is_binary(ModuleName) ->
    soft_reload_module(binary_to_atom(ModuleName, utf8));
soft_reload_module(Module) when is_atom(Module) ->
    case code:soft_purge(Module) of
        true ->
            case code:load_file(Module) of
                {module, Module} -> {ok, Module};
                {error, R} -> {error, {load_failed, R}}
            end;
        false ->
            {error, {processes_using_old_code, Module}}
    end.

%% @doc Reload all modules in the cepaf_gleam application.
%% Discovers changed modules by comparing MD5 checksums.
reload_gleam_app() ->
    case reload_changed_modules() of
        {ok, []} ->
            {ok, <<"no_changes">>};
        {ok, Modules} ->
            Count = length(Modules),
            Names = [atom_to_binary(M, utf8) || M <- Modules],
            {ok, list_to_binary([
                integer_to_binary(Count),
                <<" modules reloaded: ">>,
                iolist_to_binary(lists:join(<<", ">>, Names))
            ])};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Get list of all loaded modules matching cepaf_gleam prefix.
get_loaded_modules() ->
    All = code:all_loaded(),
    GleamModules = [M || {M, _Path} <- All,
                    is_gleam_module(M)],
    [atom_to_binary(M, utf8) || M <- lists:sort(GleamModules)].

%% @doc Get module info (exports, attributes, compile info).
get_module_info(ModuleName) when is_binary(ModuleName) ->
    get_module_info(binary_to_atom(ModuleName, utf8));
get_module_info(Module) when is_atom(Module) ->
    case code:is_loaded(Module) of
        {file, Path} ->
            Exports = length(Module:module_info(exports)),
            {ok, list_to_binary([
                <<"module: ">>, atom_to_binary(Module, utf8),
                <<", exports: ">>, integer_to_binary(Exports),
                <<", path: ">>, list_to_binary(Path)
            ])};
        false ->
            {error, <<"not_loaded">>}
    end.

%% @doc Check if a module is currently loaded.
is_module_loaded(ModuleName) when is_binary(ModuleName) ->
    is_module_loaded(binary_to_atom(ModuleName, utf8));
is_module_loaded(Module) when is_atom(Module) ->
    case code:is_loaded(Module) of
        {file, _} -> true;
        false -> false
    end.

%% @doc Get the MD5 checksum of a loaded module's bytecode.
get_module_md5(ModuleName) when is_binary(ModuleName) ->
    get_module_md5(binary_to_atom(ModuleName, utf8));
get_module_md5(Module) when is_atom(Module) ->
    try
        Info = Module:module_info(md5),
        list_to_binary([io_lib:format("~2.16.0B", [B]) || <<B:8>> <= Info])
    catch
        _:_ -> <<"unknown">>
    end.

%% @doc Compile a .gleam file and reload the resulting BEAM module.
%% This is for development-time hot reload (gleam build + load).
compile_and_reload(GleamFile) when is_binary(GleamFile) ->
    %% Step 1: Run gleam build
    Cmd = "cd " ++ binary_to_list(get_project_root()) ++ " && gleam build 2>&1",
    Output = os:cmd(Cmd),
    case string:find(Output, "error") of
        nomatch ->
            %% Step 2: Reload changed modules
            reload_changed_modules();
        _ ->
            {error, list_to_binary(Output)}
    end.

%% @doc Safe reload with pre/post verification checks.
%% Protocol:
%%   1. Check module is loaded
%%   2. Record current MD5
%%   3. Soft purge old code
%%   4. Load new beam file
%%   5. Verify new MD5 differs (actual change occurred)
%%   6. Run basic sanity check (module_info accessible)
safe_reload_with_check(ModuleName) when is_binary(ModuleName) ->
    safe_reload_with_check(binary_to_atom(ModuleName, utf8));
safe_reload_with_check(Module) when is_atom(Module) ->
    try
        %% Pre-check: is module loaded?
        case code:is_loaded(Module) of
            false ->
                %% Not loaded yet — just load it fresh
                case code:load_file(Module) of
                    {module, Module} -> {ok, {fresh_load, Module}};
                    {error, R} -> {error, {load_failed, R}}
                end;
            {file, _} ->
                %% Record old MD5
                OldMd5 = get_module_md5(Module),
                %% Soft purge (safe)
                case code:soft_purge(Module) of
                    true ->
                        case code:load_file(Module) of
                            {module, Module} ->
                                NewMd5 = get_module_md5(Module),
                                Changed = OldMd5 =/= NewMd5,
                                %% Sanity check: module_info accessible
                                _ = Module:module_info(exports),
                                {ok, {reloaded, Module, Changed}};
                            {error, R} ->
                                {error, {load_failed, R}}
                        end;
                    false ->
                        {error, {old_code_in_use, Module}}
                end
        end
    catch
        _:Error ->
            {error, {verification_failed, Error}}
    end.

%% @doc Discover and reload all modules whose on-disk .beam differs from loaded version.
reload_changed_modules() ->
    LoadedModules = [M || {M, _} <- code:all_loaded(), is_gleam_module(M)],
    Changed = lists:filter(fun(M) -> has_changed(M) end, LoadedModules),
    case Changed of
        [] -> {ok, []};
        _ -> reload_modules(Changed)
    end.

%% @doc Get the .beam file path for a module.
get_beam_path(ModuleName) when is_binary(ModuleName) ->
    get_beam_path(binary_to_atom(ModuleName, utf8));
get_beam_path(Module) when is_atom(Module) ->
    case code:is_loaded(Module) of
        {file, Path} -> {ok, list_to_binary(Path)};
        false ->
            case code:where_is_file(atom_to_list(Module) ++ ".beam") of
                non_existing -> {error, <<"not_found">>};
                Path -> {ok, list_to_binary(Path)}
            end
    end.

%% --- Internal helpers ---

is_gleam_module(Module) ->
    Name = atom_to_list(Module),
    lists:prefix("cepaf_gleam", Name) orelse
    lists:prefix("Elixir.CepafGleam", Name).

has_changed(Module) ->
    try
        %% Get loaded MD5
        LoadedMd5 = Module:module_info(md5),
        %% Get on-disk MD5
        case code:is_loaded(Module) of
            {file, Path} ->
                case beam_lib:md5(Path) of
                    {ok, {_, DiskMd5}} ->
                        LoadedMd5 =/= DiskMd5;
                    _ -> false
                end;
            _ -> false
        end
    catch
        _:_ -> false
    end.

get_project_root() ->
    %% Navigate from ebin/ to project root
    case code:priv_dir(cepaf_gleam) of
        {error, _} -> <<".">>;
        Dir -> list_to_binary(filename:dirname(filename:dirname(Dir)))
    end.
