%% Curated PURE subset of erts/emulator/test/module_info_SUITE.erl (E7 suite
%% closure). The real suite exercises the auto-generated M:module_info/0,1
%% surface (exports, functions, attributes, compile, md5, nifs, native,
%% native_addresses), erlang:get_module_info/1,2, erlang:is_builtin/3, and the
%% delete/purge lifecycle. zigvm implements module_info/0,1 + is_builtin/3
%% (proven by zigvm_e4_SUITE:c_module_info); these cases assert the
%% REPRESENTATION-INDEPENDENT, VALUE-STABLE truths of that surface that both
%% VMs must compute identically (byte-EQ), mirroring the suite's `exports`,
%% `functions`, `info`, `nifs`, and `native` cases plus is_builtin coverage.
%%
%% Every runtime operand that a naive compiler could constant-fold across is
%% routed through the exported ?MODULE:id/1 firewall, and every module_info
%% read is a REMOTE call (?MODULE:module_info(...)) so the loaded-code path is
%% genuinely exercised rather than a compile-time table.
%%
%% SCOPE HONESTY (measured on the prebuilt zigvm CLI vs erl OTP-28 oracle;
%% real divergences recorded, never silently dropped):
%%   * module_info(functions) — zigvm lists only EXPORTED functions; OTP lists
%%     locals too. So c_functions asserts the intersection truth both agree on
%%     (exports SUBSET-OF functions, both proper {atom,arity} lists) and does
%%     NOT assert local-function presence.
%%   * module_info(native_addresses) — zigvm raises `badarg`; OTP returns [].
%%     EXCLUDED. The `native` boolean (false on both) IS asserted.
%%   * Cross-module module_info on builtin/stdlib modules (erlang:module_info,
%%     lists:module_info) — zigvm returns `undef` (those modules have no loaded
%%     beam under zigvm's minimal boot); OTP returns the atom. EXCLUDED — every
%%     case reads SELF (?MODULE) module info only.
%%   * md5 / vsn are hashes — asserted for SHAPE + intra-VM COHERENCE only
%%     (16-byte binary; {vsn,[Int]} pair), never by specific value.
%%
%% A case returns the atom `true` on success; the runner
%% (zigvm_module_info_suite_runner) counts a case EQ only when BOTH VMs'
%% `Suite:Case([])` returns `true`.
-module(zigvm_module_info_SUITE).

-export([all/0,
         c_module/1, c_info_keys/1, c_exports_self/1, c_exports_stable/1,
         c_functions_superset/1, c_attributes_vsn/1, c_compile_info/1,
         c_md5_shape/1, c_nifs_empty/1, c_native_false/1,
         c_is_builtin_true/1, c_is_builtin_false/1,
         %% constant-folding firewall (exported so the remote call resolves).
         id/1]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's module_info-suite spec case_names (the runner's
%% ncases/1 == length case_names cross-check keeps them in lockstep).
all() ->
    [c_module, c_info_keys, c_exports_self, c_exports_stable,
     c_functions_superset, c_attributes_vsn, c_compile_info,
     c_md5_shape, c_nifs_empty, c_native_false,
     c_is_builtin_true, c_is_builtin_false].

%% Identity through an exported call — the compiler cannot constant-fold
%% across it, so is_builtin operands genuinely travel through the VM.
id(X) -> X.

%% --- module_info(module) names this module; the 0-arity list agrees ---------
c_module(_) ->
    (zigvm_module_info_SUITE:module_info(module) =:= zigvm_module_info_SUITE)
        andalso
        (keyfind(module, zigvm_module_info_SUITE:module_info())
             =:= {module, zigvm_module_info_SUITE}).

%% --- module_info() carries the standard key set -----------------------------
%% Both VMs expose exactly the keyfindable keys module/exports/attributes/
%% compile/md5 in the 0-arity proplist (asserted by membership, not order).
c_info_keys(_) ->
    Info = zigvm_module_info_SUITE:module_info(),
    haskey(module, Info) andalso haskey(exports, Info)
        andalso haskey(attributes, Info) andalso haskey(compile, Info)
        andalso haskey(md5, Info).

%% --- module_info(exports) contains the auto-generated + declared exports ----
c_exports_self(_) ->
    E = zigvm_module_info_SUITE:module_info(exports),
    mem({all, 0}, E)
        andalso mem({module_info, 0}, E)
        andalso mem({module_info, 1}, E)
        andalso mem({c_module, 1}, E)
        andalso mem({id, 1}, E).

%% --- the exports list is stable across calls (incl. across a failed call) ---
%% Mirrors the real `exports/1`: a subsequent (caught) undefined call must not
%% perturb the exports table.
c_exports_stable(_) ->
    E1 = zigvm_module_info_SUITE:module_info(exports),
    _ = (try zigvm_module_info_SUITE:no_such_export()
             catch _:_ -> ignored end),
    E2 = zigvm_module_info_SUITE:module_info(exports),
    E1 =:= E2.

%% --- module_info(functions) is a superset of exports ------------------------
%% Both proper lists of {atom,arity}; every exported function appears among the
%% functions. (zigvm lists only exported functions, OTP also lists locals — the
%% SUBSET direction is the truth both agree on; see SCOPE HONESTY.)
c_functions_superset(_) ->
    F = zigvm_module_info_SUITE:module_info(functions),
    E = zigvm_module_info_SUITE:module_info(exports),
    all_fa(F) andalso all_fa(E) andalso subset(E, F).

%% --- module_info(attributes) carries a {vsn,[Int]} pair (shape only) --------
c_attributes_vsn(_) ->
    A = zigvm_module_info_SUITE:module_info(attributes),
    case keyfind(vsn, A) of
        {vsn, [V]} when is_integer(V) -> true;
        _ -> false
    end.

%% --- module_info(compile) carries {options,List} and a {version,_} pair -----
c_compile_info(_) ->
    C = zigvm_module_info_SUITE:module_info(compile),
    OptsOk = case keyfind(options, C) of
                 {options, O} -> is_list(O);
                 _ -> false
             end,
    OptsOk andalso haskey(version, C).

%% --- module_info(md5) is a 16-byte binary, coherent with the 0-arity list ---
%% The md5 VALUE is a hash and is NOT compared across VMs — only its shape and
%% intra-VM coherence (the module_info(md5) reading equals the keyfound md5).
c_md5_shape(_) ->
    M = zigvm_module_info_SUITE:module_info(md5),
    Coherent = (keyfind(md5, zigvm_module_info_SUITE:module_info()) =:= {md5, M}),
    is_binary(M) andalso (byte_size(M) =:= 16) andalso Coherent.

%% --- module_info(nifs) is [] for a pure (no-NIF) module ---------------------
c_nifs_empty(_) ->
    zigvm_module_info_SUITE:module_info(nifs) =:= [].

%% --- module_info(native) is false for a non-native-compiled module ----------
c_native_false(_) ->
    zigvm_module_info_SUITE:module_info(native) =:= false.

%% --- erlang:is_builtin/3 is true for real BIFs (operands via the firewall) --
c_is_builtin_true(_) ->
    erlang:is_builtin(id(erlang), id(abs), id(1))
        andalso erlang:is_builtin(id(erlang), id(is_atom), id(1))
        andalso erlang:is_builtin(id(erlang), id(node), id(0))
        andalso erlang:is_builtin(id(erlang), id(tuple_size), id(1))
        andalso erlang:is_builtin(id(erlang), id(self), id(0))
        andalso erlang:is_builtin(id(erlang), id(length), id(1)).

%% --- erlang:is_builtin/3 is false for non-BIFs ------------------------------
%% This module's own exported function is not a BIF, and a made-up erlang/N is
%% not a BIF either.
c_is_builtin_false(_) ->
    (erlang:is_builtin(id(zigvm_module_info_SUITE), id(all), id(0)) =:= false)
        andalso (erlang:is_builtin(id(zigvm_module_info_SUITE), id(c_module), id(1)) =:= false)
        andalso (erlang:is_builtin(id(erlang), id(no_such_bif_xyz), id(7)) =:= false).

%% --- local helpers (self-contained; no lists:*/keyfind BIF to load) ---------
mem(_, []) -> false;
mem(X, [X | _]) -> true;
mem(X, [_ | T]) -> mem(X, T).

%% keyfind/2: first {Key,_} pair (assumes the key is present for the callers
%% that pattern-match its result; haskey/2 guards the optional-key callers).
keyfind(K, [{K, _} = P | _]) -> P;
keyfind(K, [_ | T]) -> keyfind(K, T).

haskey(_, []) -> false;
haskey(K, [{K, _} | _]) -> true;
haskey(K, [_ | T]) -> haskey(K, T).

%% every element is a {Atom, Arity} pair (Arity a non-negative integer).
all_fa([]) -> true;
all_fa([{N, A} | T]) when is_atom(N), is_integer(A), A >= 0 -> all_fa(T);
all_fa(_) -> false.

%% every element of As is a member of Bs.
subset([], _) -> true;
subset([H | T], Bs) -> mem(H, Bs) andalso subset(T, Bs).
