%% corpus_seed — the differential Erlang corpus (E0.6, whole-VM homomorphism v0).
%%
%% Every function here is PURE, DETERMINISTIC, and — critically — expressible
%% within the E0 CLI calling convention (`zigvm run corpus_seed.beam <fn>
%% [ints]`, cf. src/cli.zig): a 0-arg or integer-argument export returning a
%% printable term. The two-step arity rule in cli.run means an arity-1 export
%% receives all int args as one proper list in x0, so list-taking functions are
%% driven by passing the list elements as separate int arguments.
%%
%% These functions therefore compile down to ONLY the op/BIF envelope the VM
%% implements today (loader.supported_ops + instr_algebra.supported_bifs):
%% integer `+`/`-` behind gc_bif2, cons/head/tail list build+deconstruct,
%% integer comparison, recursion, calls. E1 (the ISA-totality epoch) widened the
%% op envelope so the RESULT path now also admits TUPLES (`put_tuple2`/
%% `get_tuple_element`), MAPS (`put_map_assoc`/`get_map_elements`), ATOMS,
%% COMPARISON GUARDS (`is_ge`), TYPE-TEST GUARDS (`is_integer`), TRY/CATCH
%% (`try`/`try_case`/`case_end`), CLOSURES (`make_fun3`/`call_fun2`) and SELECT
%% jump tables (`select_val`) — see the E1 section below. Still OUT of the E0
%% CLI envelope: compile-time FLOAT / large literals (LitT literal-table operands
%% are not yet decoded — W-17/M9), and `*`/`div`/`rem`/`bsl` (unsupported BIFs —
%% E2). Bignums are produced by RUNTIME repeated addition (doubling), never a
%% folded literal, so the 2^59 small/big boundary is genuinely exercised through
%% the executor.
%%
%% The remaining rich domains that CANNOT be expressed within this convention —
%% total-term-order (lists:sort), atom-comparison, exact-vs-arithmetic-equality,
%% and FLOAT arithmetic (`X + 0.0`, which needs a LitT float literal — W-17 — or a
%% BIF, so it load-rejects; recorded `rich_float`) — are exercised ORACLE-SIDE
%% ONLY from the printer (zigvm_case_printer.erl) and recorded
%% UNTESTED(calling-convention) on the zigvm side — honestly, never silently
%% dropped (SC-8.2 / conformance rule "UNTESTED is visible").
-module(corpus_seed).
-export([my_dummy_net_kernel/0, my_dist_ctrl/1, dist_channel_live/1,
         sum_list/1, rev_list/1, len_list/1, range/1, factsum/1,
         arith/0, bignum/0, big_neg/1, doubler/1, add_pair/2,
         nth3/1, plus_minus/1, countdown_sum/1,
         %% E1 ISA-totality cases (tuples/maps/guards/try/funs/select)
         tup_swap/2, tup_mid/3, cmp_ge/2, is_int_test/1, trycatch/1,
         try_class/1, stk_line/1,
         closure/1, map_get1/2, tagged/1, sel/1,
         %% E3.4 bit-syntax construction<->matching round-trip cases
         bs_int16/1, bs_int_le/1, bs_two_ints/2, bs_signed/1,
         bs_utf8_rt/1, bs_utf16_rt/1, bs_tail/2, bs_append/2,
         %% E3.12 static multi-module dispatch (call_ext / apply/3)
         err_catch/1, throw_catch/1, exit_catch/1, pdict/1, apply_add/2,
         %% E3.18 E2 fast-follow sweep (predicates / min-max / checksums /
         %% calendar / ets-core) — every case a pure int-returning round-trip
         %% that byte-matches on both VMs.
         pred_check/1, minmax/2, crc_of/1, adler_of/1, cal_rt/1, ets_take_v/1,
         ets_rename_v/1,
         %% E3.12b static multi-module dispatch: fully-qualified calls into the
         %% corpus_dep dependency module, linked via `--pa` across .beam files.
         xadd/2, xchain/1,
         %% E3.13 fun/module introspection: is_builtin/3 (pin bif.tab) and
         %% function_exported/3 (the linked export index), both call_ext BIFs.
         builtin_check/1, fnexp_check/1,
         %% E7.7 debugger-capability query (erl_debugger:supported/0 -> false).
         dbg_sup/1,
         %% E3.15 ets match/select family (matchspec-term compiler).
         ets_select_v/1, ets_selcount_v/1, ets_matchspec_v/1, ets_selchunk_v/1,
         %% E3.16 ets duplicate_bag (S22): exact-duplicate retention.
         ets_dbag_v/1,
         %% E3.17 big Unicode tables (S9): characters_to_binary/list round-trip
         %% over the ENLARGED domain (ASCII/Latin-1/Greek/supplementary plane).
         uni_rt/1,
         %% E4.1 scheduler-as-driver: the process-effect BIFs (spawn/3, send,
         %% register/whereis, monitor/DOWN, link+trap_exit/EXIT), each a
         %% multi-process round-trip returning an int that byte-matches on both
         %% VMs. pchild/2, pwaiter/1, pboom/0, exit_waiter/0 are the spawned entry points.
         pspawn/1, preg/1, palive/1, pmon/1, plink/1,
         pchild/2, pwaiter/1, pboom/0, exit_waiter/0,
         %% E21.1 (DIVERGENCE 450): spawn/1 + spawn_link/1 of a FUN (closure spawn).
         %% pspawn_fun spawns a fun that captures the parent pid + N and sends N
         %% back; plink_fun spawn_links a fun that boots, trapped as {'EXIT',P,boom}.
         pspawn_fun/1, plink_fun/1,
         %% e4-registered0: register/2 + registered/0 registry-backed round-trip
         pregall/1,
         %% E4.2: module metadata via get_module_info (M:module_info/0,1)
         mi_md5/1, mi_mod/1,
         %% E4.2b: erts_internal:beamfile_chunk/2 over a synthetic IFF container
         bfc/1, bfc_absent/1,
         %% E6.8: the strict FORM-SIZE domain (DIVERGENCE 108 discharge)
         bfc_bigform/1, bfc_trailing/1,
         %% E4.4: prim_file:/file: native-name codec (all five bif.tab rows)
         nne_rt/1,
         %% E4.6: the io / group-leader protocol — group_leader/0 EQ (a BOOL).
         gl_not_self/1,
         %% E5.4: the live os-port driver — open_port/port_command/port_close +
         %% port_set_data/port_get_data over a real `cat` (both VMs spawn it).
         port_echo/1, port_data_rt/1,
         %% E5.5 (Task 5) the alias-signal model: alias delivery + post-unalias
         %% drop + monitor-alias DOWN-retirement + async is_process_alive/2.
         palias/1, malias/1,
         alias_sender/2, alias_dropper/2, mchild/1,
         %% E5.2c: the RELOAD half's PURE row — beamfile_module_md5/1 over a real
         %% embedded beam blob (no stdlib file I/O). Runs BEFORE code_q.
         bfmd5/1,
         %% e5-dispatch-codeidx: a LIVE reload — prepare_loading/2 + finish_loading/1
         %% over the embedded zmini blob, then CALL zmini:z() through the runtime
         %% code table (call_ext now consults code_index). Runs BEFORE code_q.
         reload_call/1,
         %% E7.2 (DIVERGENCE 147): the on_load STAGING trio — has_prepared_code_on_
         %% load/1 + finish_loading -> {on_load,[Mod]} + call_on_load_function/1 +
         %% finish_after_on_load/2 over an embedded on_load beam blob. Runs BEFORE code_q.
         onload_call/1,
         %% E6.3 (DIVERGENCE 108): the erts_code_purger / erts_literal_area_collector
         %% PROCESS restriction — a direct (non-purger) call raises error:notsup on
         %% BOTH VMs. Runs BEFORE code_q (order-independent; no code-table effect).
         purge_notsup/1, litarea_notsup/1,
         %% E6.4 (DIVERGENCE 112): the process-suspension + system-task family —
         %% the suspend/resume counting monoid (balanced -> true), is_system_process
         %% (-> false for a normal proc), garbage_collect (-> true), system_check
         %% (schedulers -> ok). Byte-identical on both VMs. Runs BEFORE code_q.
         suspend_fam/1, suspend_waiter/0,
         %% E5.2b: the file-based code-server QUERY BIFs — check_old_code/1 +
         %% delete_module/1 over the mutable two-version code table (must be LAST:
         %% it retires corpus_seed's own current version).
         code_q/1,
         %% E5.6 (Task 6) the async spawn/request protocol: spawn_request/4 +
         %% spawn_request_abandon/1 + erts_internal:process_flag/3 (save_calls).
         sreq/1, pf3/1, sreq_child/1, pf3_child/1,
         %% E8.2b non-distributed nodes/1,2 observer subset.
         nodes_opts/1,
         %% E8.2c no-carrier dist local observers.
         dist_local_obs/1,
         %% E8.2e pinned OTP30 no-carrier DFLAG record.
         dflags_obs/1,
         %% E8.2d no-carrier monitor_node/2,3 observer subset.
         monitor_node_obs/1,
         %% E8.2f erts_debug:dist_ext_to_term/2 debug dist-external decoder.
         dist_ext_decode/1,
         %% E8.2g no-carrier dist control-data rejection surface.
         dist_ctrl_nohandle/1,
         %% E8.2i no-carrier remote spawn request direct-BIF surface.
         dist_spawn_no_conn/1,
         %% E8.2j no-socket pending dist connection-id surface.
         dist_pending_conn/1,
         %% E8.2k no-carrier channel-start rejection surface.
         dist_channel_start_no_carrier/1,
         %% E8.2h no-carrier exit_signal/2,3 identity surface.
         exit_signal_obs/1,
         %% E5.7 (Task 7) external (foreign-node) pid/port/ref TERMS via ETF.
         fpid/1,
         %% E5.3 (Task 3) the GL SETTER pair erts_internal:group_leader/2,3,
         %% observed representation-free via the child's own group_leader/0.
         glset/1, glset_child/0,
         %% E5.8b (Task 8b) the time/OS-clock family + os env: PROPERTY-folded to
         %% a deterministic {true,true,true,true} on both VMs (never a raw clock
         %% VALUE) — type, monotonicity, offset identity, timestamp shape, env
         %% round-trip. See DIVERGENCE entry 93.
         tclock/1, tosenv/1,
         %% E6.2 (Task 2) the LIVE receive/BIF timer family: `receive after N` +
         %% send_after/start_timer/cancel_timer/read_timer. Deterministic results
         %% (after-clause value, delivered message, and the `false` a fired/cancelled
         %% timer reports) — the timing-dependent remaining-ms is NEVER asserted.
         recv_after/1, send_after_self/1, start_timer_self/1,
         cancel_fired/1, read_cancelled/1,
         %% E6.5 (Task 5): the system introspection family, PROPERTY-folded to
         %% deterministic boolean/constant tuples on both VMs (counters/settings
         %% are host-nondeterministic or pid-repr-specific; only monotonicity,
         %% integer type, and set/get round-trips are observed — never a raw VALUE).
         stat_props/1, sysinfo_const/1, flag_roundtrip/1, bump_red/1,
         profile_roundtrip/1, monitor_roundtrip/1, swt_roundtrip/1,
         dirty_pure/1, dirty_rows/1,
         %% E6.7 (Task 7): the multi-process ETS-ownership + port-representation
         %% surface, flipped end-to-end via representation-FREE / rejection
         %% differentials (owner/heir pids, port name strings, membership, the
         %% control-verb `badarg` return). See DIVERGENCE entry 124.
         port_verbs/1, port_conn/1, port_conn_child/1,
         ets_giveaway/1, ets_heir/1, ets_whereis/1,
         %% E7.3 (DIVERGENCE 143): shared ETS — cross-process table visibility.
         ets_shared/1, ets_shared_child/1,
         %% E7.5 (DIVERGENCE 154): hibernate/3 MFA-reentry, end-to-end.
         phibernate/1, hib_loop/2,
         %% E7.6 (DIVERGENCE 158): the honestly-observable tracing surface —
         %% seq_trace token round-trip, dt_* non-dtrace constants/identity,
         %% seq_trace_print / trace_info empty-trace answers.
         seq_trace_surface/1, dt_surface/1, trace_query/1,
         %% E7.9: hosted re engine over the stdlib byte-PCRE subset.
         re_simple/1, re_global/1, re_import_rt/1,
         %% e21-t2 (DIVERGENCE 490): node/0 bif-trap dst-delivery fix
         node_self_eq/1,
         %% e21-t2b (DIVERGENCE 510 / 490-amend): spawned-child compound-literal
         %% send (the OOB-panic fix) + process_info/2 dispatch wiring
         child_lit_send/1, pinfo_regname/1, lit_sender/1]).

%% --- M3: list ops via structural recursion (cons/head/tail + `+`) ---
sum_list([]) -> 0;
sum_list([H | T]) -> H + sum_list(T).

rev_list(L) -> rev_list(L, []).
rev_list([], Acc) -> Acc;
rev_list([H | T], Acc) -> rev_list(T, [H | Acc]).

len_list([]) -> 0;
len_list([_ | T]) -> 1 + len_list(T).

range(0) -> [];
range(N) -> [N | range(N - 1)].

%% sum of N..1 built by structural recursion over the counter (arith over a
%% computed descent) — distinct code path from sum_list/range.
factsum(0) -> 0;
factsum(N) -> N + factsum(N - 1).

%% --- M1: integer arithmetic ---
arith() -> 2 + 3 + 4 - 1.

%% --- M1: bignum crossing 2^59 by RUNTIME repeated doubling (no literal) ---
%% dbl(1, 59) == 2^59 computed by 59 self-additions; +5 lands just past the
%% 60-bit small/big boundary, so the result is a heap bignum.
bignum() -> dbl(1, 59) + 5.
dbl(Acc, 0) -> Acc;
dbl(Acc, K) -> dbl(Acc + Acc, K - 1).

%% --- M1: a large NEGATIVE bignum (magnitude built at runtime, arg-driven) ---
big_neg(K) -> 0 - (dbl(1, 60) + K).

%% --- M1: trivial arity-1 / arity-2 arithmetic ---
doubler(X) -> X + X.
add_pair(A, B) -> A + B.

%% --- M3: list pattern-match observation (third element via head/tail) ---
nth3([_, _, C | _]) -> C.

%% --- M1: mixed +/- chain ---
plus_minus(X) -> X + 10 - 3.

%% --- M1+M3: composition — sum of a runtime-built list ---
countdown_sum(N) -> sum_list(range(N)).

%% === E1 ISA-totality cases (each stays within the E0 int-in / printable-out
%% CLI convention; each exercises an opcode class E1 added; the printer echoes
%% its seed via the shared `CASE <fn> <term>` stream) ===

%% E1.5 tuples: build {A,B} (put_tuple2), destructure it (get_tuple_element),
%% return the swapped tuple {B,A} in the RESULT path.
tup_swap(A, B) -> {X, Y} = {A, B}, {Y, X}.

%% E1.5 tuples: extract the middle element of a 3-tuple by pattern match
%% (get_tuple_element with a mid index), return the int.
tup_mid(A, B, C) -> {_, M, _} = {A, B, C}, M.

%% E1.4 comparison guard: `>=` compiles to is_ge; integer max via a guard.
cmp_ge(A, B) -> if A >= B -> A; true -> B end.

%% E1.3 type-test guard: is_integer over the (always-integer) CLI arg → an atom
%% result, exercising the type_test .integer arm and an atom in the RESULT path.
is_int_test(X) -> case is_integer(X) of true -> yes; false -> no end.

%% E1.8 try/catch: a case with no matching clause raises {case_clause,_}; the
%% try frame catches it (try/try_case/case_end). X=0 hits the clause (zero);
%% any other X is caught (caught) — both branches printable atoms.
trycatch(X) ->
    try case X of 0 -> zero end
    catch error:_ -> caught end.

%% E3.10: OBSERVE the exception CLASS (the new thing) and reason-atom through a
%% `try ... catch Class:Reason -> {Class,Reason}`. `X div 0` crashes badarith
%% via a reachable gc_bif2 (no call_ext, no stacktrace observed), so both VMs
%% produce `{error, badarith}` — the class-discrimination law, end-to-end.
%% (throw/exit class cases need throw/1,exit/1 which are call_ext -> Task 12.)
try_class(X) ->
    try X div 0
    catch Class:Reason -> {Class, Reason} end.

%% E3.11: OBSERVE the cooked STACKTRACE (DIVERGENCE entry 2b). A `case_clause`
%% is raised DIRECTLY in the function body (not via a BIF, so the head frame is
%% the FUNCTION frame on both VMs), then the stacktrace's head is pattern-matched
%% to its exact shape `{M,F,A,[{file,_},{line,L}]}` and the line int returned.
%% Both VMs cook the same line from the `Line` chunk -> the head-frame exactness
%% law, end-to-end. Returns the int (a charlist file would diverge on print
%% format — BEAM shows "..." for a printable list, zigvm shows the int list —
%% so the FILE is matched-but-ignored, only the LINE int is observed).
stk_line(X) ->
    try case X of 0 -> zero end
    catch _:_:S -> {_, _, _, [{file, _}, {line, L}]} = hd(S), L end.

%% E3.12: static multi-module dispatch — the exception-raising family
%% (erlang:error/1, throw/1, exit/1) and the process dictionary (put/2, get/1,
%% erase/1) and apply/3 are now reachable end-to-end because `call_ext`
%% dispatches (Task 12). Each was call_ext-blocked before this slice.

%% erlang:error/1 (call_ext_only) raised and caught by CLASS error -> reason X.
err_catch(X) -> try erlang:error(X) catch error:R -> R end.

%% throw/1 (call_ext_only) caught by CLASS throw -> the thrown value X.
throw_catch(X) -> try throw(X) catch throw:R -> R end.

%% exit/1 (call_ext_only, the CATCHABLE raise form) caught by CLASS exit -> X.
exit_catch(X) -> try exit(X) catch exit:R -> R end.

%% process dictionary round-trip: put/2 (call_ext), get/1 (guard-bif), erase/1
%% (call_ext_only). put(k,X) then read it back then erase it -> X.
pdict(X) -> put(k, X), V = get(k), _ = erase(k), V.

%% erlang:apply/3 (call_ext) dispatching a BIF target: apply(erlang,'+',[A,B]).
%% The apply/3 == call_ext law made differential (both VMs return A+B).
apply_add(A, B) -> apply(erlang, '+', [A, B]).

%% E3.18: the type/guard predicates (is_integer/is_number/is_atom) — a guard
%% over the fast-follow family. For an integer X: true -> X + 1.
pred_check(X) ->
    case is_integer(X) andalso is_number(X) andalso (not is_atom(X)) of
        true -> X + 1;
        false -> 0
    end.

%% E3.18: min/2 and max/2 (the arith-order selectors) combined into one int.
minmax(A, B) -> min(A, B) * 1000 + max(A, B).

%% E3.18: erlang:crc32/1 (zlib CRC-32) over a deterministic char list — both
%% VMs compute the identical checksum.
crc_of(X) -> erlang:crc32(integer_to_list(X)).

%% E3.18: erlang:adler32/1 (zlib Adler-32) over the same char list.
adler_of(X) -> erlang:adler32(integer_to_list(X)).

%% E3.18: the pure Gregorian-calendar inverse pair round-trips a POSIX second.
cal_rt(S) -> erlang:universaltime_to_posixtime(erlang:posixtime_to_universaltime(S)).

%% E3.18: ets:take/2 (lookup+remove over the live TreeBackend) round-trips X.
ets_take_v(X) ->
    T = ets:new(t, [set]),
    true = ets:insert(T, {k, X}),
    case ets:take(T, k) of
        [{k, V}] -> V;
        _ -> -1
    end.

%% E5.9: ets:rename/2 — a named table is renamed, then reached by the NEW name
%% (the objects survive the remap). Returns X unchanged (a name-registry remap
%% is denotation-preserving on the object multiset).
ets_rename_v(X) ->
    ets:new(orig, [set, named_table]),
    true = ets:insert(orig, {k, X}),
    fresh = ets:rename(orig, fresh),
    case ets:lookup(fresh, k) of
        [{k, V}] -> V;
        _ -> -1
    end.

%% E3.15: the ets match/select family, driven by the runtime matchspec-term
%% compiler. Every case a pure int-returning round-trip that byte-matches on
%% both VMs (ordered_set so the result ORDER is BEAM-deterministic; only the
%% bif.tab-level BIFs are called, never ets.erl library wrappers).

%% Insert keys K..1 with value X+K into T (ascending on read-back).
ins_kv(_, _, 0) -> ok;
ins_kv(T, X, K) -> true = ets:insert(T, {K, X + K}), ins_kv(T, X, K - 1).

%% ets:select value-body: sum the '$2' of rows with key > 2 -> (X+3)+(X+4).
ets_select_v(X) ->
    T = ets:new(t, [ordered_set]),
    ins_kv(T, X, 4),
    sum_list(ets:select(T, [{{'$1', '$2'}, [{'>', '$1', 2}], ['$2']}])).

%% ets:select_count over the [true]-predicate compiler: how many keys > X.
ets_selcount_v(X) ->
    T = ets:new(t, [ordered_set]),
    ins_kv(T, 0, 5),
    ets:select_count(T, [{{'$1', '$2'}, [{'>', '$1', X}], [true]}]).

%% match_spec_compile + is_compiled_ms + erlang:match_spec_test/3 (table).
%% The compiled MS is opaque on both VMs; test on {5,X} (key 5 > 2) -> body '$2'.
ets_matchspec_v(X) ->
    MS = [{{'$1', '$2'}, [{'>', '$1', 2}], ['$2']}],
    C = ets:match_spec_compile(MS),
    true = ets:is_compiled_ms(C),
    {ok, R, _, _} = erlang:match_spec_test({5, X}, MS, table),
    R.

%% continuation select/3 + select/1: chunk the whole table (limit 2), sum every
%% value exactly once -> (X+1)+(X+2)+(X+3)+(X+4).
ets_selchunk_v(X) ->
    T = ets:new(t, [ordered_set]),
    ins_kv(T, X, 4),
    chunk_sum(ets:select(T, [{{'$1', '$2'}, [], ['$2']}], 2), 0).
chunk_sum('$end_of_table', Acc) -> Acc;
chunk_sum({Rows, Cont}, Acc) -> chunk_sum(ets:select(Cont), Acc + sum_list(Rows)).

%% E3.16: duplicate_bag RETAINS exact-duplicate objects (a bag would dedupe to
%% one), and delete_object removes ALL equal copies. Insert {k,X} three times
%% -> lookup length 3; delete_object once -> length 0. Result 30 (== 3*10+0)
%% byte-matches on both VMs (host OTP-28 has duplicate_bag).
ets_dbag_v(X) ->
    T = ets:new(t, [duplicate_bag]),
    O = {k, X},
    true = ets:insert(T, O),
    true = ets:insert(T, O),
    true = ets:insert(T, O),
    N = length(ets:lookup(T, k)),
    true = ets:delete_object(T, O),
    M = length(ets:lookup(T, k)),
    N * 10 + M.

%% --- E3.17: big Unicode tables (S9) — enlarged-domain codec round-trip ---
%% uni_rt drives the real `unicode:characters_to_binary/2` + `characters_to_list/2`
%% BIFs (call_ext-dispatched) over a codepoint list spanning ALL the byte-width
%% classes: ASCII 'A' (65, 1 byte), Latin-1 'é' (233, 2 bytes), Greek 'α' (945,
%% 2 bytes) and Deseret capital long-I U+10400 (66560, 4 bytes, SUPPLEMENTARY
%% plane). Encoding to a UTF-8 binary then decoding back and summing the
%% codepoints must yield the same int on both VMs (65+233+945+66560 = 67803) —
%% the E2.12 subset laws re-asserted over the enlarged domain the case tables
%% define, and a genuine plane-1 differential the host oracle also evaluates.
uni_rt(Cps) ->
    Bin = unicode:characters_to_binary(Cps, utf8),
    Back = unicode:characters_to_list(Bin, utf8),
    sum_list(Back).

%% E4.4 native-name codec: drives ALL FIVE prim_file:/file: bif.tab rows
%% (call_ext-dispatched) — internal_name2native/1 (UTF-8-encode a name + NUL),
%% internal_native2name/1 (decode back, keeping the NUL codepoint 0),
%% internal_normalize_utf8/1 (NFC decode), is_translatable/1 (valid UTF-8?),
%% file:native_name_encoding/0 (the atom utf8). Both round-trip sums include the
%% appended NUL; the encoding/translatable flags fold into distinct decades so a
%% miscoded byte OR a wrong encoding atom perturbs the printed int. Host OTP-28
%% evaluates the real NIFs; byte-identical on both VMs over the utf8 encoding.
nne_rt(Cps) ->
    Native = prim_file:internal_name2native(Cps),
    Back = prim_file:internal_native2name(Native),
    Norm = prim_file:internal_normalize_utf8(Native),
    Enc = case file:native_name_encoding() of utf8 -> 1; latin1 -> 2 end,
    Transl = case prim_file:is_translatable(Native) of true -> 1; false -> 2 end,
    sum_list(Back) + sum_list(Norm) + (Enc * 1000000) + (Transl * 100000).

%% E1.7 closures: build a fun that captures A (make_fun3 with a 1-var env) and
%% call it (call_fun2); returns A + 10.
closure(A) -> F = fun(Y) -> Y + A end, F(10).

%% E1.10 maps: build a 2-key map (put_map_assoc), read one key back by pattern
%% match (get_map_elements); returns the int at key 1. Integer keys avoid any
%% map print-order question (the int is what is printed).
map_get1(A, B) -> M = #{1 => A, 2 => B}, #{1 := V} = M, V.

%% E1.5 tagged tuple in the RESULT path: {tag, X} (put_tuple2 with an atom tag).
tagged(X) -> {tag, X}.

%% E1.6 select_val: a literal-keyed case compiles to a select_val jump table;
%% returns a distinct atom per arm.
sel(X) -> case X of 1 -> one; 2 -> two; _ -> other end.

%% === E3.4 bit-syntax CONSTRUCTION<->MATCHING round-trip cases (bs_create_bin
%% + the E3.3 matcher family) — the LA-3 homomorphism made differential: real
%% OTP and this VM must construct+re-match to the SAME recovered value. Real
%% bit-syntax construction MASKS an out-of-range field to its declared width
%% (e.g. `<<300:8>>` keeps only the low 8 bits), so every case here is exact
%% for ANY integer CLI arg — no precondition on X's range. ===

%% bs_int16: a 16-bit big-endian round-trip.
bs_int16(X) ->
    Bin = <<X:16>>,
    <<Y:16>> = Bin,
    Y.

%% bs_int_le: a 16-bit LITTLE-endian round-trip (the flag-decode path).
bs_int_le(X) ->
    Bin = <<X:16/little>>,
    <<Y:16/little>> = Bin,
    Y.

%% bs_two_ints: two 8-bit segments IN ORDER — the construction↔matching
%% round-trip's segment-ORDER law made differential (a reversed-write bug
%% would swap A and B on read-back).
bs_two_ints(A, B) ->
    Bin = <<A:8, B:8>>,
    <<X:8, Y:8>> = Bin,
    {X, Y}.

%% bs_signed: a SIGNED 8-bit round-trip — `(X rem 128) - 64` stays within
%% -64..63, always representable exactly in a signed 8-bit field.
bs_signed(X0) ->
    X = (X0 rem 128) - 64,
    Bin = <<X:8/signed>>,
    <<Y:8/signed>> = Bin,
    Y.

%% bs_utf8_rt: a codepoint round-tripped through a UTF-8 bit-syntax segment,
%% bounded to 1..128 so it is always a valid, non-surrogate codepoint.
bs_utf8_rt(Cp0) ->
    Cp = (Cp0 rem 128) + 1,
    Bin = <<Cp/utf8>>,
    <<C/utf8>> = Bin,
    C.

%% bs_utf16_rt: a codepoint round-tripped through a LITTLE-endian UTF-16
%% segment, bounded to 1..0x10000 so BOTH the BMP and the surrogate-pair
%% (>= 0x10000) encodings are exercised across the seed sweep.
bs_utf16_rt(Cp0) ->
    Cp = (Cp0 rem 65536) + 1,
    Bin = <<Cp/utf16-little>>,
    <<C/utf16-little>> = Bin,
    C.

%% bs_tail: a 3-segment binary (two 8-bit ints then a literal byte), matched
%% apart via a leading fixed field + a trailing `/binary` tail; returns the
%% tail binary itself (exercises `bs_get_tail`, and the DIAG binary print
%% shape on the RESULT path). NOTE: returning `byte_size(Rest)` instead would
%% let the compiler fuse the size read directly onto the match CONTEXT
%% (skipping `get_tail` entirely) — a real, separate BIF-over-live-MatchCtx
%% surface this task does not cover; returning `Rest` itself keeps this case
%% squarely inside E3.4's `bs_get_tail` opcode.
bs_tail(A, B) ->
    Bin = <<A:8, B:8, 7:8>>,
    <<_:8, Rest/binary>> = Bin,
    Rest.

%% bs_append: `bs_init_writable` + an `append` segment growing a binary
%% across TWO separate `bs_create_bin` calls, then matched back apart.
bs_append(A, B) ->
    W = <<>>,
    Bin1 = <<W/binary, A:8>>,
    Bin2 = <<Bin1/binary, B:8>>,
    <<X:8, Y:8>> = Bin2,
    {X, Y}.

%% --- E3.12b: cross-module dispatch into corpus_dep (linked via --pa) ---
%% xadd/2 reaches corpus_dep:add/2 AND corpus_dep:helper/1; xchain/1 reaches
%% corpus_dep:chain/1 (which itself calls corpus_dep:helper + add). A correct
%% int result proves cross-module call_ext dispatch over the linked program.
xadd(A, B) -> corpus_dep:add(A, B) + corpus_dep:helper(A).
xchain(X) -> corpus_dep:chain(X).

%% --- E3.13: fun/module introspection BIFs (call_ext -> call_ext_bif) ---
%% builtin_check: erlang:is_builtin/3 over the pin's bif.tab — erlang:abs/1 IS a
%% builtin (true), lists:foldl/3 is a library function (false). Result {true,
%% false} byte-matches on both VMs (~w == diag.formatValue).
builtin_check(_) ->
    {erlang:is_builtin(erlang, abs, 1), erlang:is_builtin(lists, foldl, 3)}.

%% fnexp_check: erlang:function_exported/3 over the linked export index —
%% corpus_seed:sum_list/1 IS exported (true), corpus_seed:nope/0 is not (false).
fnexp_check(_) ->
    {erlang:function_exported(corpus_seed, sum_list, 1),
     erlang:function_exported(corpus_seed, nope, 0)}.

%% dbg_sup: E7.7 (Task 7) — erl_debugger:supported/0 is a STATIC debugger-
%% capability flag (whether the emulator was built with `+D`). zigvm has no
%% debugger subsystem so it truthfully answers `false`; the host is a non-debug
%% build, also `false`. The atom byte-matches (~w prints `false`) on both VMs —
%% the end-to-end proof flipping erl_debugger:supported/0 EQ.
dbg_sup(_) ->
    erl_debugger:supported().

%% --- E4.1: process-effect BIFs via the scheduler-as-driver ---
%% Each returns the input int N (matching on process-identity WILDCARDS or on
%% `=:=`/atom results, never on a pid VALUE, so the byte-output is N on both
%% VMs). The spawned entry points (pchild/pwaiter/pboom) are exported so
%% spawn/3's MFA resolves against the linked export index on zigvm.
pchild(Parent, N) -> Parent ! N.
pwaiter(Parent) -> receive go -> Parent ! done end.
pboom() -> exit(boom).
exit_waiter() -> receive stop -> ok after 5000 -> ok end.

%% pspawn: spawn(?MODULE, pchild, [self(), N]) delivers N back — spawn/3 + send
%% + receive round-trip. Returns N.
pspawn(N) ->
    Parent = self(),
    _P = spawn(corpus_seed, pchild, [Parent, N]),
    receive X -> X end.

%% pspawn_fun: E21.1 (DIVERGENCE 450) — spawn/1 of a FUN. The fun captures the
%% parent pid and N in its closure ENV; the child runs `F()`, which sends N back.
%% Proves closure env-capture + send-receive-between-spawned via a compiled fun
%% (the primitive that resolved to `undef` before E21.1 wired spawn/1 EQ). Ret N.
pspawn_fun(N) ->
    Parent = self(),
    _P = spawn(fun() -> Parent ! N end),
    receive X -> X end.

%% plink_fun: E21.1 (DIVERGENCE 450) — spawn_link/1 of a fun that boots. With
%% trap_exit, the child's abnormal exit propagates as {'EXIT',ChildPid,boom} to
%% the parent (the link installed atomically before the child ran). Ret N.
plink_fun(N) ->
    process_flag(trap_exit, true),
    P = spawn_link(fun() -> exit(boom) end),
    receive {'EXIT', P, boom} -> N end.

%% preg: register/whereis/unregister bijection — whereis =:= self() (a BOOL,
%% EQ), then undefined after unregister. Returns N.
preg(N) ->
    register(corpus_reg, self()),
    true = (whereis(corpus_reg) =:= self()),
    unregister(corpus_reg),
    undefined = whereis(corpus_reg),
    N.

%% palive: is_process_alive(self()) is true. Returns N.
palive(N) ->
    true = is_process_alive(self()),
    N.

%% gl_not_self: E4.6 (Task 6) — the calling process's group leader is a DISTINCT
%% process, not itself (the OTP shell/user GL; the zigvm `standard_io` GL fixture
%% installed by the CLI). A BOOL observation (never a raw pid — pid VALUES differ).
%% Returns N, byte-identical on both VMs.
gl_not_self(N) ->
    true = (group_leader() =/= self()),
    N.

%% palias: E5.5 (Task 5) — the alias-signal model, end-to-end. Folds THREE
%% observations into one byte-identical int result (N):
%%   (1) ALIAS DELIVERY: a worker sends `Alias ! aha`; it lands in the owner's
%%       mailbox while the alias is active (`receive aha`).
%%   (2) RETIREMENT: `unalias(Alias)` returns true (an active caller-owned
%%       alias); a second `unalias` returns false; a subsequent send via the
%%       retired alias is DROPPED. The worker sends `Alias ! via_alias` THEN a
%%       direct `Me ! sync` — receiving `sync` proves the worker ran both, and
%%       `receive via_alias after 0 -> dropped` then confirms the alias send
%%       never arrived (per-pair order: had it arrived, it would precede sync).
%%   (3) ASYNC is_process_alive/2: the reply `{Ref, true}` arrives in the
%%       mailbox (the alias-reply protocol).
%% Every value matched is an atom/bool/wildcard, never a raw pid or ref VALUE,
%% so the case byte-matches host OTP-28 despite ref/pid representation.
palias(N) ->
    Alias = alias([]),
    Me = self(),
    spawn(corpus_seed, alias_sender, [Alias, aha]),
    receive aha -> ok end,
    true = unalias(Alias),
    false = unalias(Alias),
    spawn(corpus_seed, alias_dropper, [Alias, Me]),
    receive sync -> ok end,
    dropped = receive via_alias -> arrived after 0 -> dropped end,
    Ref = make_ref(),
    ok = erts_internal:is_process_alive(Me, Ref),
    receive {Ref, true} -> ok end,
    N.

%% alias_sender/alias_dropper: spawned entry points for palias (spawn/3, since
%% spawn/1-of-a-fun is not wired end-to-end this epoch).
alias_sender(Alias, Tag) -> Alias ! Tag.
alias_dropper(Alias, Me) -> Alias ! via_alias, Me ! sync.

%% malias: E5.5 — monitor-alias DOWN-retirement. `monitor(process,P,[{alias,
%% demonitor}])` returns a ref that is BOTH a monitor ref and an alias; when P
%% dies the 'DOWN' is delivered AND the alias auto-retires (mode /=
%% explicit_unalias). A subsequent send via that ref is then dropped — observed
%% exactly like palias's (2). Returns N.
malias(N) ->
    Me = self(),
    P = spawn(corpus_seed, mchild, [Me]),
    A = monitor(process, P, [{alias, demonitor}]),
    P ! go,
    receive {'DOWN', A, process, _, _} -> ok end,
    spawn(corpus_seed, alias_dropper, [A, Me]),
    receive sync -> ok end,
    dropped = receive via_alias -> arrived after 0 -> dropped end,
    N.

%% mchild: waits for `go`, then exits normal (firing the monitor 'DOWN').
mchild(_Me) -> receive go -> ok end.

%% sreq: E5.6 (Task 6) — the async spawn/request protocol, end-to-end. Uses
%% erts_internal:spawn_request/4 DIRECTLY (the bif.tab row; erlang:spawn_request/4
%% is an erlang.erl wrapper this VM does not load). Folds four host-DETERMINISTIC
%% observations into one int (N):
%%   (1) SPAWN-REPLY PROTOCOL: the request returns a ReqId ref; the caller
%%       receives EXACTLY the `{spawn_reply, ReqId, ok, Pid}` success message
%%       carrying that SAME ReqId (guard `Ref =:= RID`) and a pid (`is_pid(Pid)`).
%%   (2) the child actually RAN (`from_child` arrives) — a real spawn, not a stub.
%%   (3) ABANDON AFTER the reply → false (the reply is already delivered).
%%   (4) ABANDON of a FOREIGN ref (make_ref/0) → false.
%% Every match is a bool/atom/wildcard — never a raw ref/pid VALUE — so N is
%% byte-identical on both VMs. (The abandon-BEFORE-reply `true` is NOT here: it
%% is a host RACE, not deterministic — a proc.zig Vm law instead. DIVERGENCE 72.)
sreq(N) ->
    Me = self(),
    RID = erts_internal:spawn_request(corpus_seed, sreq_child, [Me], []),
    true = is_reference(RID),
    receive {spawn_reply, Ref, ok, Pid} when Ref =:= RID, is_pid(Pid) -> ok end,
    receive from_child -> ok end,
    false = erlang:spawn_request_abandon(RID),
    false = erlang:spawn_request_abandon(make_ref()),
    N.

%% sreq_child: spawned by sreq via spawn_request; proves the child ran.
sreq_child(Me) -> Me ! from_child.

%% pf3: E5.6 (Task 6) — erts_internal:process_flag/3 (`save_calls`), end-to-end.
%% The SELF form is SYNCHRONOUS (returns the OLD flag value, an int); the
%% cross-process form returns a REF (async {ReqId,Old} reply). Folds three
%% host-DETERMINISTIC observations into one int (N):
%%   (1) self save_calls 0 -> 3 returns the old value 0;
%%   (2) reading it back (3 -> 0) returns the old value 3;
%%   (3) a NON-self target returns a reference (the async request form).
%% Only ints/bools are matched (never a raw ref VALUE), so N byte-matches.
pf3(N) ->
    0 = erts_internal:process_flag(self(), save_calls, 3),
    3 = erts_internal:process_flag(self(), save_calls, 0),
    P = spawn(corpus_seed, pf3_child, [self()]),
    true = is_reference(erts_internal:process_flag(P, save_calls, 5)),
    P ! stop,
    N.

%% pf3_child: a live target for pf3's cross-process process_flag/3.
pf3_child(_Me) -> receive stop -> ok end.

%% fpid: E5.7 (Task 7) — external (foreign-node) pid/port/ref TERMS via ETF.
%% `binary_to_term` of a hand-built NEW_PID_EXT / V4_PORT_EXT / NEWER_REFERENCE_EXT
%% from node 'other@host' yields a FIRST-CLASS identity whose node/1 is the
%% foreign atom and whose term_to_binary re-encodes BYTE-IDENTICALLY (the byte-
%% comparable EQ evidence — verified against the OTP oracle). Folds is_pid/
%% is_port/is_reference, node/1, and the byte round-trip into one int (N). Only
%% atoms/bools are matched — NEVER the printed <N.x.y>, whose node-table index is
%% a per-node non-deterministic slot we do not model — so N byte-matches host OTP
%% end-to-end. This is the sole host-DETERMINISTIC distribution surface reachable
%% without a live second node (the dist carrier/handshake BIFs stay deferred).
fpid(N) ->
    PidBin = <<131,88,119,10,"other@host",0,0,0,100,0,0,0,7,0,0,0,3>>,
    P = binary_to_term(PidBin),
    true = is_pid(P),
    'other@host' = node(P),
    PidBin = term_to_binary(P),
    PortBin = <<131,120,119,10,"other@host",0,0,0,0,0,0,0,5,0,0,0,3>>,
    Port = binary_to_term(PortBin),
    true = is_port(Port),
    'other@host' = node(Port),
    PortBin = term_to_binary(Port),
    RefBin = <<131,90,0,3,119,10,"other@host",0,0,0,9,0,0,0,1,0,0,0,2,0,0,0,3>>,
    R = binary_to_term(RefBin),
    true = is_reference(R),
    'other@host' = node(R),
    RefBin = term_to_binary(R),
    N.

%% nodes_opts: E8.2b — the non-distributed `nodes/1,2` observer subset.
%% No carrier is started. The stable oracle facts are: connected/visible/hidden
%% are empty, known/this select `nonode@nohost`, and the `nodes/2` info map only
%% reports requested boolean keys (`node_type => this`, `connection_id =>
%% undefined`). The case folds to N so no carrier/process representation leaks
%% into the byte comparison.
nodes_opts(N) ->
    [] = erlang:nodes(connected),
    [Self] = erlang:nodes(known),
    [] = erlang:nodes([visible, hidden]),
    [Self] = erlang:nodes([this]),
    [{Self, #{}}] = erlang:nodes(known, #{}),
    [{Self, #{node_type := this, connection_id := undefined}}] =
        erlang:nodes([known, this], #{node_type => true, connection_id => true}),
    [{Self, #{connection_id := undefined}}] =
        erlang:nodes(known, #{node_type => false, connection_id => true}),
    [] = erlang:nodes(connected, #{node_type => true}),
    N.

%% dist_local_obs: E8.2c — no-carrier distribution observers. The host facts are
%% `erts_internal:get_creation() == undefined`, `dflag_unicode_io(self()) == true`,
%% and an ETF-created foreign pid has no unicode-io DFLAG, so false. Runs after
%% nodes_opts (which must observe the no-foreign-node `nodes(known)` state) and
%% before fpid.
dist_local_obs(N) ->
    undefined = erts_internal:get_creation(),
    true = net_kernel:dflag_unicode_io(self()),
    P = binary_to_term(<<131,88,119,10,"other@host",0,0,0,100,0,0,0,7,0,0,0,3>>),
    false = net_kernel:dflag_unicode_io(P),
    N.

%% dflags_obs: E8.2e — pinned OTP30 no-carrier distribution flags. This exact
%% record is build/pin-coupled and deliberately separate from live peer DFLAG
%% exchange, which still belongs to the dist-carrier control-channel slice.
dflags_obs(N) ->
    {erts_dflags,468283523004,17230663572,468283523004,8396866,8192} =
        erts_internal:get_dflags(),
    N.

%% monitor_node_obs: E8.2d — no-carrier monitor_node/2,3 observer subset. Local
%% toggles return true; a foreign atom raises error:notalive; /3 admits [] and
%% the bare allow_passive_connect option but rejects invalid option terms.
monitor_node_obs(N) ->
    true = erlang:monitor_node(node(), true),
    true = erlang:monitor_node(node(), false),
    true = erlang:monitor_node(node(), true, []),
    true = erlang:monitor_node(node(), true, [allow_passive_connect]),
    try erlang:monitor_node('other@host', true) of
        _ -> error(unexpected_monitor_node_remote)
    catch
        error:notalive -> ok
    end,
    try erlang:monitor_node(node(), 'maybe') of
        _ -> error(unexpected_monitor_node_flag)
    catch
        error:badarg -> ok
    end,
    try erlang:monitor_node(node(), true, bad) of
        _ -> error(unexpected_monitor_node_opts)
    catch
        error:badarg -> ok
    end,
    N.

%% dist_ext_decode: E8.2f — erts_debug:dist_ext_to_term/2 is a debug decoder
%% over an atom-cache tuple plus a versioned binary, not a live distribution
%% channel handle. Exercise ordinary ETF bytes, nested ATOM_CACHE_REF (`$R`),
%% and out-of-range cache-ref rejection. Fold to N; no representation leaks.
dist_ext_decode(N) ->
    1 = erts_debug:dist_ext_to_term({}, <<131,97,1>>),
    {1,foo} = erts_debug:dist_ext_to_term({foo}, <<131,104,2,97,1,82,0>>),
    [foo,2] = erts_debug:dist_ext_to_term({foo}, <<131,108,0,0,0,2,82,0,97,2,106>>),
    try erts_debug:dist_ext_to_term({foo}, <<131,82,1>>) of
        _ -> error(unexpected_dist_ext_cache_ref)
    catch
        error:badarg -> ok
    end,
    N.

%% dist_ctrl_nohandle: E8.2g - no live distribution controller or internal
%% dist_handle exists in zigvm. OTP30's direct-call surface raises notsup for
%% controller-owned get/notify/option/input-handler calls and badarg for
%% put_data/stat invalid handles. Fold to N; no dhandle value is printed.
dist_ctrl_nohandle(N) ->
    try erlang:dist_ctrl_get_data(0) of
        _ -> error(unexpected_dist_get_data)
    catch error:notsup -> ok end,
    try erlang:dist_ctrl_get_data_notification(0) of
        _ -> error(unexpected_dist_get_data_notification)
    catch error:notsup -> ok end,
    try erlang:dist_ctrl_get_opt(0, get_size) of
        _ -> error(unexpected_dist_get_opt)
    catch error:notsup -> ok end,
    try erlang:dist_ctrl_input_handler(0, self()) of
        _ -> error(unexpected_dist_input_handler)
    catch error:notsup -> ok end,
    try erlang:dist_ctrl_set_opt(0, get_size, true) of
        _ -> error(unexpected_dist_set_opt)
    catch error:notsup -> ok end,
    try erlang:dist_ctrl_put_data(0, <<>>) of
        _ -> error(unexpected_dist_put_data_bin)
    catch error:badarg -> ok end,
    try erlang:dist_ctrl_put_data(0, []) of
        _ -> error(unexpected_dist_put_data_nil)
    catch error:badarg -> ok end,
    try erlang:dist_get_stat(0) of
        _ -> error(unexpected_dist_get_stat)
    catch error:badarg -> ok end,
    N.

%% dist_spawn_no_conn: E8.2i — direct erts_internal:dist_spawn_request/4 on a
%% foreign atom while no distribution carrier is installed. The direct BIF
%% returns a fresh request reference (or {Ref,Bool} for spawn_opt shape) and
%% sends the local error reply for no connection unless reply options suppress
%% error replies. Folded to N; no raw ref is printed.
dist_spawn_no_conn(N) ->
    R1 = erts_internal:dist_spawn_request('other@host', {erlang, self, []}, [], spawn_request),
    true = is_reference(R1),
    receive {spawn_reply, R1, error, noconnection} -> ok after 0 -> error(missing_dist_spawn_reply) end,

    R2 = erts_internal:dist_spawn_request('other@host', {erlang, self, []}, [{reply, no}], spawn_request),
    true = is_reference(R2),
    receive {spawn_reply, R2, error, _} -> error(unexpected_dist_spawn_reply) after 0 -> ok end,

    R3 = erts_internal:dist_spawn_request('other@host', {erlang, self, []}, [{reply_tag, mytag}], spawn_request),
    true = is_reference(R3),
    receive {mytag, R3, error, noconnection} -> ok after 0 -> error(missing_dist_spawn_tag_reply) end,

    R4 = erts_internal:dist_spawn_request('other@host', {erlang, self, []}, [{reply, bad}], spawn_request),
    true = is_reference(R4),
    receive {spawn_reply, R4, error, badopt} -> ok after 0 -> error(missing_dist_spawn_badopt_reply) end,

    {R5, true} = erts_internal:dist_spawn_request('other@host', {erlang, self, []}, [monitor], spawn_opt),
    true = is_reference(R5),
    receive {spawn_reply, R5, error, noconnection} -> ok after 0 -> error(missing_dist_spawn_opt_reply) end,

    {R6, false} = erts_internal:dist_spawn_request('other@host', {erlang, self, []}, [], bad_mode),
    true = is_reference(R6),
    receive {spawn_reply, R6, error, noconnection} -> ok after 0 -> error(missing_dist_spawn_mode_reply) end,

    badarg = erts_internal:dist_spawn_request(node(), {erlang, self, []}, [], spawn_request),
    badarg = erts_internal:dist_spawn_request('other@host', {erlang, self, []}, bad, spawn_request),
    badarg = erts_internal:dist_spawn_request('other@host', {erlang, self, bad}, [], spawn_request),
    N.

%% dist_pending_conn: E8.2j — direct pending connection handles before a live
%% distribution channel exists. new_connection/1 creates/reuses a pending
%% {ConnId,Ref}; abort_pending_connection/2 validates the node/handle identity,
%% returns true, and leaves the next new_connection with a higher ConnId but the
%% same node handle ref. Folded to N; no raw ref/id is printed.
dist_pending_conn(N) ->
    N1 = 'other@host',
    N2 = 'more@host',
    C1 = erts_internal:new_connection(N1),
    {I1, R1} = C1,
    true = is_integer(I1),
    true = is_reference(R1),

    C1 = erts_internal:new_connection(N1),
    C3 = erts_internal:new_connection(N2),
    {I3, R3} = C3,
    true = is_integer(I3),
    true = is_reference(R3),
    true = C3 =/= C1,

    true = erts_internal:abort_pending_connection(N1, C1),
    true = erts_internal:abort_pending_connection(N1, C1),
    C4 = erts_internal:new_connection(N1),
    {I4, R1} = C4,
    true = I4 > I1,

    try erts_internal:abort_pending_connection(N2, C1) of
        _ -> error(unexpected_abort_wrong_node)
    catch error:badarg -> ok end,
    try erts_internal:abort_pending_connection(N1, make_ref()) of
        _ -> error(unexpected_abort_bad_handle)
    catch error:badarg -> ok end,
    try erts_internal:new_connection(foo) of
        _ -> error(unexpected_new_connection_bad_node)
    catch error:badarg -> ok end,
    try erts_internal:new_connection(node()) of
        _ -> error(unexpected_new_connection_local_node)
    catch error:badarg -> ok end,
    N.

%% dist_channel_start_no_carrier: E8.2k — direct channel-start calls before a
%% live distribution carrier exists. setnode/2 raises badarg; create_dist_channel/3
%% returns atom badarg and installs no channel. Folded to N.
dist_channel_start_no_carrier(N) ->
    try erlang:setnode('other@host', 4) of
        _ -> error(unexpected_setnode_ok)
    catch error:badarg -> ok end,
    try erlang:setnode(foo, 0) of
        _ -> error(unexpected_setnode_bad_node_ok)
    catch error:badarg -> ok end,

    badarg = erts_internal:create_dist_channel('other@host', self(), {468283523004, 4}),
    badarg = erts_internal:create_dist_channel('other@host', self(), {0, 0}),
    badarg = erts_internal:create_dist_channel(foo, self(), {0, 1}),
    C = erts_internal:new_connection('other@host'),
    true = erts_internal:abort_pending_connection('other@host', C),
    badarg = erts_internal:create_dist_channel('other@host', self(), {468283523004, 4}),
    N.

%% exit_signal_obs: E8.2h — OTP30's lower-level exit_signal/2,3 surface that is
%% executable without a live distribution carrier. Local pid/ref/port identities
%% are admitted; foreign pid/ref identities are inert true; invalid destinations
%% or option lists raise badarg. Folded to N so no pid/ref/port value is printed.
exit_signal_obs(N) ->
    P1 = spawn(corpus_seed, exit_waiter, []),
    true = erlang:exit_signal(P1, normal),
    true = is_process_alive(P1),
    true = erlang:exit_signal(P1, normal, [priority]),
    true = is_process_alive(P1),
    P1 ! stop,

    P2 = spawn(corpus_seed, exit_waiter, []),
    true = erlang:exit_signal(P2, kill),
    receive after 20 -> ok end,
    false = is_process_alive(P2),

    A = alias([]),
    true = erlang:exit_signal(A, normal),
    true = unalias(A),
    true = erlang:exit_signal(A, normal),

    FP = binary_to_term(<<131,88,119,10,"other@host",0,0,0,100,0,0,0,7,0,0,0,3>>),
    true = erlang:exit_signal(FP, normal),
    FR = binary_to_term(<<131,90,0,3,119,10,"other@host",0,0,0,9,0,0,0,1,0,0,0,2,0,0,0,3>>),
    true = erlang:exit_signal(FR, normal, [priority]),

    try erlang:exit_signal(self(), normal, [bad]) of
        _ -> error(unexpected_exit_signal_badopt)
    catch error:badarg -> ok end,
    try erlang:exit_signal(self(), normal, [priority|bad]) of
        _ -> error(unexpected_exit_signal_improper_opts)
    catch error:badarg -> ok end,
    try erlang:exit_signal(0, normal) of
        _ -> error(unexpected_exit_signal_bad_dest)
    catch error:badarg -> ok end,
    N.

%% glset: E5.3 (Task 3) — the GL SETTER pair erts_internal:group_leader/2,3.
%% A child process starts with its INHERITED group leader (=/= the parent); the
%% parent retargets it to ITSELF via erts_internal:group_leader/2, then asks the
%% child to report its OWN group_leader/0 (the already-EQ get form). The result
%% is compared representation-free (`=:= self()`), so no raw pid VALUE is ever
%% printed — N byte-matches on both VMs iff the setter took effect. Discharges
%% the deferred-E5-io SETTER clause (DIVERGENCE entry 40/41 amended).
glset(N) ->
    Parent = self(),
    P = spawn(corpus_seed, glset_child, []),
    true = erts_internal:group_leader(Parent, P),
    P ! {gl, Parent},
    receive
        {mygl, GL} ->
            case GL =:= Parent of
                true -> N;
                false -> -1
            end
    end.

glset_child() ->
    receive
        {gl, From} -> From ! {mygl, group_leader()}
    end.

%% pregall: e4-registered0 — register/2 + registered/0 end-to-end,
%% registry-backed (registered/0 used to be constant [] — see
%% bifs/procsys.zig's doc comment). registered() on the REAL oracle also
%% carries the node's boot-time system names (application_controller,
%% code_server, …), so this asserts SET-MEMBERSHIP of the name THIS process
%% registered (via lists:member/2 — a REAL bif.tab row, unlike lists:sort/1
%% which is pure Erlang library code with no zigvm stdlib to resolve it)
%% rather than the raw list — the same SET-equality discipline as the E4.2
%% module_info(exports) precedent (DIVERGENCE entry 29), never a false-EQ on
%% a raw-list byte compare. (A pid may hold only ONE registered name — the
%% registry bijection — so a single name is registered here; the SORTED-
%% canonicalization/multiple-name ordering law is proven directly in
%% proc.zig's Zig law suite instead, over several distinct pids.) Returns N.
pregall(N) ->
    register(corpus_pregall_name, self()),
    Names = registered(),
    true = lists:member(corpus_pregall_name, Names),
    false = lists:member(corpus_absent_name, Names),
    unregister(corpus_pregall_name),
    N.

%% pmon: monitor a child, wake it, then observe its 'DOWN' (wildcards on
%% ref/pid/reason). Returns N.
pmon(N) ->
    Parent = self(),
    P = spawn(corpus_seed, pwaiter, [Parent]),
    _Ref = monitor(process, P),
    P ! go,
    receive done -> ok end,
    receive {'DOWN', _, process, _, _} -> N end.

%% plink: trap_exit + spawn_link a boomer, observe the {'EXIT', Pid, boom}
%% message binding the SPECIFIC child pid (proves the pid-term EXIT sender).
%% Returns N.
plink(N) ->
    process_flag(trap_exit, true),
    P = spawn_opt(corpus_seed, pboom, [], [link]),
    receive {'EXIT', P, boom} -> N end.

%% --- E4.2: module metadata via M:module_info/0,1 -> erlang:get_module_info ---
%% Each reaches erlang:get_module_info(corpus_seed, Key) through the compiler-
%% generated module_info/1 (call_ext -> call_ext_bif). The keys asserted here
%% print IDENTICALLY under `~w` == diag.formatValue AND are byte-EQ because BOTH
%% VMs load the SAME corpus_seed.beam: md5 is the 16-byte checksum
%% (beam_loader.computeMd5 == erts' module checksum), module is the atom. The
%% `exports` key is NOT asserted — erts orders module_info(exports) by internal
%% global-atom-index (erl_bif_info.c exported_from_module), an ordering this
%% VM's atom table does not reproduce (DIVERGENCE entry 29): same {F,A} SET,
%% different order.
mi_md5(_) -> module_info(md5).
mi_mod(_) -> module_info(module).

%% --- E4.2b: erts_internal:beamfile_chunk/2 over a SYNTHETIC IFF container ---
%% beamfile_chunk/2 is PURE over its raw beam-binary ARGUMENT (it never touches
%% the code table), so a compiled `.beam` can build a minimal well-formed
%% `FOR1 <size> BEAM <chunk-id> <chunk-size> <payload>` container inline (plain
%% 8-bit byte segments, no string-in-binary syntax) and BOTH VMs return the SAME
%% extracted payload / `undefined`. "Atom"=[65,116,111,109]; the container
%% carries one "Atom" chunk with payload <<1,2,3,4>>.
beam_bin() ->
    <<70,79,82,49, 0,0,0,16, 66,69,65,77, 65,116,111,109, 0,0,0,4, 1,2,3,4>>.
%% EXTRACTION: the found chunk's payload bytes, verbatim (<<1,2,3,4>>).
bfc(_) -> erts_internal:beamfile_chunk(beam_bin(), "Atom").
%% ABSENCE: a chunk not present in the container → the atom `undefined`.
bfc_absent(_) -> erts_internal:beamfile_chunk(beam_bin(), "AtU8").
%% E6.8 (DIVERGENCE 108 discharge): the STRICT FORM-SIZE domain. erts' iff
%% reader honours the `FOR1` form-size field; zigvm's OLD lenient walk ignored
%% it and DIVERGED. Two cases pin the boundary against the real host:
%%   bfc_bigform — form_size=20 over a 28-byte binary whose trailing 4 bytes are
%%     a truncated chunk header: the "Atom" chunk IS present at [12,24) yet the
%%     malformed tail makes the WHOLE file invalid → `undefined` on erts (and now
%%     on zigvm). This is the exact input the old lenient walk got WRONG
%%     (returned <<1,2,3,4>>).
bfc_bigform(_) ->
    Bin = <<70,79,82,49, 0,0,0,20, 66,69,65,77, 65,116,111,109, 0,0,0,4, 1,2,3,4, 9,9,9,9>>,
    erts_internal:beamfile_chunk(Bin, "Atom").
%%   bfc_trailing — form_size=16 over the SAME 28-byte binary: the form ends at
%%     byte 24, so the trailing 4 bytes are OUTSIDE the form and ignored → the
%%     chunk IS returned (<<1,2,3,4>>) on both VMs. Proves trailing-after-form is
%%     tolerated identically (not over-strict).
bfc_trailing(_) ->
    Bin = <<70,79,82,49, 0,0,0,16, 66,69,65,77, 65,116,111,109, 0,0,0,4, 1,2,3,4, 9,9,9,9>>,
    erts_internal:beamfile_chunk(Bin, "Atom").

%% --- E5.4: the LIVE os-port driver over a real `cat` -----------------------
%% Both VMs spawn the SAME external program (`cat`), so this is a genuine
%% differential (the oracle twin E4.5's fixture echo lacked). The erts_internal
%% primitives may return either a value OR an async reference (erlang.erl's own
%% idiom) — both branches are handled so the fixture is identical on the OTP-28
%% host and on zigvm. Results are ints (the echoed / stored byte), never a Port
%% VALUE, so they byte-match despite port-representation differences.
op_open(Name, Opts) ->
    case erts_internal:open_port(Name, Opts) of
        R when is_reference(R) -> receive {R, Res} -> Res end;
        Res -> Res
    end.
op_cmd(P, D) ->
    case erts_internal:port_command(P, D, []) of
        R when is_reference(R) -> receive {R, Res} -> Res end;
        Res -> Res
    end.
op_close(P) ->
    case erts_internal:port_close(P) of
        R when is_reference(R) -> receive {R, Res} -> Res end;
        Res -> Res
    end.

%% open cat, echo one byte through the OS pipe, close; return the echoed byte.
%% The reply binary D crosses the owner's mailbox and is decoded via a DIRECT
%% `<<B:8>>` bit-match (vm-binmatch-gc, DIVERGENCE 57/68 — was formerly read via
%% binary_to_list to sidestep the bs_start_match3 operand-order bug; now the
%% end-to-end differential proof that a received binary bit-matches, EQ vs OTP).
port_echo(N) ->
    P = op_open({spawn, "cat"}, [binary]),
    true = op_cmd(P, <<N:8>>),
    R = receive {P, {data, D}} -> <<B:8>> = D, B after 2000 -> timeout end,
    _ = op_close(P),
    R.

%% open cat, store an opaque term on the port, read it back, close; return it.
port_data_rt(N) ->
    P = op_open({spawn, "cat"}, [binary]),
    true = erlang:port_set_data(P, N),
    V = erlang:port_get_data(P),
    _ = op_close(P),
    V.

%% E5.2b: the file-based code-server QUERY BIFs over the mutable two-version
%% code table (DIVERGENCE 61). Drives the RUNTIME two-version transition:
%% check_old_code false (loaded, no old) -> delete_module true (retires current
%% to old) -> check_old_code true (old now exists) -> delete_module of an ABSENT
%% module is `undefined`. Returns {false,true,true,undefined} byte-identically on
%% both VMs (no pid/port VALUE printed). MUST be the last runnable case: it
%% retires corpus_seed's own current version (harmless — the running frame keeps
%% executing as old code, the M10 continuation-stays law, and nothing calls
%% corpus_seed afterward on the shared oracle node).
%% E5.2c (Task 2 RELOAD half, DIVERGENCE 75): beamfile_module_md5/1 — the whole-
%% beam module checksum. PURE over a raw beam-binary argument (never touches the
%% code table), so the honest bif-surface source of a real beam image at runtime
%% is an EMBEDDED BINARY LITERAL — reload_beam/0 below is a real `+deterministic`
%% erlc build of `-module(zmini). z()->0.` (520 bytes). Both VMs read the SAME
%% literal and return the SAME 16-byte checksum <<221,136,43,112,...>> (the module
%% MD5 == zmini:module_info(md5), version-independent). No pid/port VALUE printed.
bfmd5(_) ->
    erts_internal:beamfile_module_md5(reload_beam()).

%% A real, +deterministic-compiled beam of `-module(zmini). -export([z/0]). z()->0.`
reload_beam() ->
    <<70,79,82,49,0,0,2,0,66,69,65,77,65,116,85,56,0,0,0,47,255,255,255,251,80,122,109,105,110,105,16,122,176,109,111,100,117,108,101,95,105,110,102,111,96,101,114,108,97,110,103,240,103,101,116,95,109,111,100,117,108,101,95,105,110,102,111,0,67,111,100,101,0,0,0,70,0,0,0,16,0,0,0,0,0,0,0,177,0,0,0,7,0,0,0,3,1,16,153,16,2,18,34,0,1,32,64,1,3,19,1,48,153,0,2,18,50,0,1,64,64,18,3,78,16,0,1,80,153,0,2,18,50,16,1,96,64,3,19,64,18,3,78,32,16,3,0,0,83,116,114,84,0,0,0,0,73,109,112,84,0,0,0,28,0,0,0,2,0,0,0,4,0,0,0,5,0,0,0,1,0,0,0,4,0,0,0,5,0,0,0,2,69,120,112,84,0,0,0,40,0,0,0,3,0,0,0,3,0,0,0,1,0,0,0,6,0,0,0,3,0,0,0,0,0,0,0,4,0,0,0,2,0,0,0,0,0,0,0,2,77,101,116,97,0,0,0,45,131,108,0,0,0,1,104,2,119,16,101,110,97,98,108,101,100,95,102,101,97,116,117,114,101,115,108,0,0,0,1,119,10,109,97,121,98,101,95,101,120,112,114,106,106,0,0,0,76,111,99,84,0,0,0,4,0,0,0,0,65,116,116,114,0,0,0,39,131,108,0,0,0,1,104,2,119,3,118,115,110,108,0,0,0,1,110,16,0,220,235,165,195,200,54,14,99,63,230,9,153,112,43,136,221,106,106,0,67,73,110,102,0,0,0,26,131,108,0,0,0,1,104,2,119,7,118,101,114,115,105,111,110,107,0,5,57,46,48,46,52,106,0,0,68,98,103,105,0,0,0,66,131,104,3,119,13,100,101,98,117,103,95,105,110,102,111,95,118,49,119,17,101,114,108,95,97,98,115,116,114,97,99,116,95,99,111,100,101,104,2,119,4,110,111,110,101,108,0,0,0,1,119,13,100,101,116,101,114,109,105,110,105,115,116,105,99,106,0,0,76,105,110,101,0,0,0,21,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,1,0,0,0,0,49,0,0,0,84,121,112,101,0,0,0,10,0,0,0,3,0,0,0,1,15,255,0,0>>.

%% e5-dispatch-codeidx (Task 2 RELOAD half, DIVERGENCE 81, amending 75): a LIVE
%% reload, end-to-end. `erts_internal:prepare_loading/2` validates the embedded
%% zmini beam (returning a magic-ref handle — host-verified), `erlang:finish_
%% loading/1` commits it, and then `zmini:z()` is CALLED through `call_ext` — which
%% now consults the RUNTIME code table (Machine.resolveRuntime / dyn_exports /
%% dyn_code), the blocker DIVERGENCE 75 named. This is the live-reload differential
%% the E5.2c investigation could not reach: the beam bytes are an EMBEDDED literal
%% (reload_beam/0, the honest bif-surface source — no stdlib file I/O / boot), the
%% handle is a reference, finish returns ok, and zmini:z() returns 0, so the whole
%% case returns N byte-identically on both VMs (no pid/port/ref VALUE printed).
reload_call(N) ->
    Bin = reload_beam(),
    P = erts_internal:prepare_loading(zmini, Bin),
    true = is_reference(P),
    ok = erlang:finish_loading([P]),
    zmini:z() + N.

% E7.2 (DIVERGENCE 147): the on_load STAGING trio, driven end-to-end. `onload_beam/0`
% is a real `+deterministic` erlc build of `-module(zonload). -export([z/0]).
% -on_load(init/0). init() -> ok. z() -> 42.` (560 bytes) — an EMBEDDED beam blob
% carrying an `-on_load` attribute (the honest bif-surface source, no stdlib file
% I/O / boot). The full host protocol (verified on OTP-28): prepare_loading -> ref;
% has_prepared_code_on_load(Ref) -> true (the beam carries on_load); finish_loading
% -> {on_load,[zonload]} (NOT `ok` — the on_load must still run + gate);
% call_on_load_function(zonload) RUNS init/0 and returns its value `ok`;
% finish_after_on_load(zonload, true) COMMITS -> true; then zonload:z() -> 42. The
% case folds to 42 + N byte-identically on both VMs (no pid/ref VALUE printed). The
% end-to-end proof flipping has_prepared_code_on_load/1 + call_on_load_function/1 +
% finish_after_on_load/2 EQ. Runs BEFORE code_q (code_q retires corpus_seed).
onload_beam() ->
    <<70,79,82,49,0,0,2,40,66,69,65,77,65,116,85,56,0,0,0,57,255,255,255,249,112,122,111,110,108,111,97,100,64,105,110,105,116,32,111,107,16,122,176,109,111,100,117,108,101,95,105,110,102,111,96,101,114,108,97,110,103,240,103,101,116,95,109,111,100,117,108,101,95,105,110,102,111,0,0,0,67,111,100,101,0,0,0,86,0,0,0,16,0,0,0,0,0,0,0,177,0,0,0,9,0,0,0,4,1,16,153,16,2,18,34,0,1,32,149,64,50,3,19,1,48,153,32,2,18,66,0,1,64,64,9,42,3,19,1,80,153,0,2,18,82,0,1,96,64,18,3,78,16,0,1,112,153,0,2,18,82,16,1,128,64,3,19,64,18,3,78,32,16,3,0,0,83,116,114,84,0,0,0,0,73,109,112,84,0,0,0,28,0,0,0,2,0,0,0,6,0,0,0,7,0,0,0,1,0,0,0,6,0,0,0,7,0,0,0,2,69,120,112,84,0,0,0,40,0,0,0,3,0,0,0,5,0,0,0,1,0,0,0,8,0,0,0,5,0,0,0,0,0,0,0,6,0,0,0,4,0,0,0,0,0,0,0,4,77,101,116,97,0,0,0,45,131,108,0,0,0,1,104,2,119,16,101,110,97,98,108,101,100,95,102,101,97,116,117,114,101,115,108,0,0,0,1,119,10,109,97,121,98,101,95,101,120,112,114,106,106,0,0,0,76,111,99,84,0,0,0,16,0,0,0,1,0,0,0,2,0,0,0,0,0,0,0,2,65,116,116,114,0,0,0,39,131,108,0,0,0,1,104,2,119,3,118,115,110,108,0,0,0,1,110,16,0,163,45,90,18,85,165,192,82,3,63,75,90,98,41,208,7,106,106,0,67,73,110,102,0,0,0,26,131,108,0,0,0,1,104,2,119,7,118,101,114,115,105,111,110,107,0,5,57,46,48,46,52,106,0,0,68,98,103,105,0,0,0,66,131,104,3,119,13,100,101,98,117,103,95,105,110,102,111,95,118,49,119,17,101,114,108,95,97,98,115,116,114,97,99,116,95,99,111,100,101,104,2,119,4,110,111,110,101,108,0,0,0,1,119,13,100,101,116,101,114,109,105,110,105,115,116,105,99,106,0,0,76,105,110,101,0,0,0,22,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,2,0,0,0,0,65,81,0,0,84,121,112,101,0,0,0,10,0,0,0,3,0,0,0,1,15,255,0,0>>.

onload_call(N) ->
    Bin = onload_beam(),
    P = erts_internal:prepare_loading(zonload, Bin),
    true = is_reference(P),
    true = erlang:has_prepared_code_on_load(P),
    {on_load,[zonload]} = erlang:finish_loading([P]),
    ok = erlang:call_on_load_function(zonload),
    true = erlang:finish_after_on_load(zonload, true),
    zonload:z() + N.

%% E6.3 (Task 3, DIVERGENCE 108, amending 75/81): the erts_code_purger PROCESS
%% restriction. `erts_internal:purge_module/2` is restricted to the code-purger
%% system process — a DIRECT call from any normal process raises `error:notsup`
%% (host-verified on OTP-28, and the process check DOMINATES arg validation:
%% purge_module(123, notabool) still raises notsup). Both VMs run this from a
%% non-purger process, so both catch `error:notsup` and fold to N — byte-EQ, no
%% pid/ref VALUE printed. The end-to-end proof flipping purge_module/2 EQ; the
%% REAL purge is driven through the boot-spawned purger (proven by the RUNTIME-
%% driven purge-safety law in code_server.zig / proc.zig).
purge_notsup(N) ->
    restricted = try erts_internal:purge_module(zigvm_absent_mod, false)
                 catch error:notsup -> restricted end,
    restricted = try erts_internal:purge_module(zigvm_absent_mod, true)
                 catch error:notsup -> restricted end,
    N.

%% E6.3 (DIVERGENCE 108): the erts_literal_area_collector PROCESS restriction.
%% release_area_switch/0 + send_copy_request/3 are restricted to the literal-area
%% collector system process — a direct (non-collector) call raises error:notsup
%% (host-verified; the process check dominates, so ATOM args to send_copy_request
%% still raise notsup). Both VMs fold to N — byte-EQ, no pid/ref VALUE printed.
%% The end-to-end proof flipping both collector rows EQ; the area switch's
%% denote-preservation is the litarea-conservation law.
litarea_notsup(N) ->
    ok = try erts_literal_area_collector:release_area_switch()
         catch error:notsup -> ok end,
    ok = try erts_literal_area_collector:send_copy_request(a, b, init)
         catch error:notsup -> ok end,
    N.

%% E6.4 (Task 4, DIVERGENCE 112): the process-SUSPENSION + system-task family.
%% The suspend/resume counting MONOID: nested suspends stack, matching resumes
%% unwind them, every balanced call returns `true` (host-verified on OTP-28). A
%% BIF-suspended child is not schedulable (proc.zig's suspend_count gated by
%% `schedulable`), but the corpus observes only the byte-total RETURN contract +
%% is_system_process (a normal process is never a system process -> false),
%% erts_internal:garbage_collect (a GC request -> true), and system_check
%% (schedulers -> ok). Each `X = call` is an ASSERTION: a wrong return crashes the
%% process and diverges the output, so the fold to N proves the family end-to-end.
%% Child blocks in `receive` so it stays alive across the suspend/resume window.
suspend_fam(N) ->
    Child = spawn(corpus_seed, suspend_waiter, []),
    true = erts_internal:suspend_process(Child, []),
    true = erts_internal:suspend_process(Child, [asynchronous]), %% nested (count 2)
    true = erlang:resume_process(Child),
    true = erlang:resume_process(Child),                         %% balanced (count 0)
    false = erts_internal:is_system_process(Child),
    false = erts_internal:is_system_process(self()),
    true = erts_internal:garbage_collect(major),
    true = erts_internal:garbage_collect(minor),
    ok = erts_internal:system_check(schedulers),
    Child ! stop,
    N.

%% the suspend_fam child: blocks in `receive` so it stays alive (and suspendable)
%% across the suspend/resume window; the trailing `stop` lets it exit cleanly.
suspend_waiter() -> receive stop -> ok end.

code_q(_) ->
    A = erlang:check_old_code(corpus_seed),
    B = erlang:delete_module(corpus_seed),
    C = erlang:check_old_code(corpus_seed),
    D = erlang:delete_module(zigvm_absent_mod),
    {A, B, C, D}.

%% E5.8b (Task 8b): the erlang time/OS-clock family, PROPERTY-folded to a
%% deterministic {true,true,true,true} on both VMs (a raw clock reading is
%% host-nondeterministic, so only the guarantees erts makes are observed):
%%   A: integer type of every reading (monotonic/system/offset).
%%   B: monotonic_time never decreases across two reads (guaranteed on both VMs).
%%   C: the offset identity — with reads ordered offset, monotonic, system, a
%%      no-time-warp offset gives system >= monotonic + offset (system time is
%%      taken LAST, so its monotonic component is >= the earlier read).
%%   D: erlang:timestamp/0 is a 3-tuple with sec/micro in range.
tclock(_) ->
    A = is_integer(erlang:monotonic_time())
        andalso is_integer(erlang:monotonic_time(millisecond))
        andalso is_integer(erlang:system_time())
        andalso is_integer(erlang:system_time(second))
        andalso is_integer(erlang:time_offset())
        andalso is_integer(erlang:time_offset(native)),
    M1 = erlang:monotonic_time(),
    M2 = erlang:monotonic_time(),
    B = M2 >= M1,
    Off = erlang:time_offset(),
    Mono = erlang:monotonic_time(),
    Sys = erlang:system_time(),
    C = Sys >= Mono + Off,
    {Mega, Sec, Micro} = erlang:timestamp(),
    D = is_integer(Mega) andalso Mega >= 0
        andalso Sec >= 0 andalso Sec < 1000000
        andalso Micro >= 0 andalso Micro < 1000000,
    {A, B, C, D}.

%% E5.8b (Task 8b): the os module family. env round-trip is host-DETERMINISTIC
%% (putenv then getenv == value; unsetenv then getenv == false), and the clock
%% rows fold the type/shape properties. {true,true,true,true} on both VMs.
tosenv(_) ->
    os:putenv("ZIGVM_E5T8B_VAR", "hi"),
    R1 = os:getenv("ZIGVM_E5T8B_VAR"),
    os:unsetenv("ZIGVM_E5T8B_VAR"),
    R2 = os:getenv("ZIGVM_E5T8B_VAR"),
    A = (R1 =:= "hi") andalso (R2 =:= false),
    B = is_integer(os:system_time())
        andalso is_integer(os:system_time(millisecond))
        andalso is_integer(os:perf_counter()),
    {OMega, OSec, OMicro} = os:timestamp(),
    C = is_integer(OMega) andalso OMega >= 0
        andalso OSec >= 0 andalso OSec < 1000000
        andalso OMicro >= 0 andalso OMicro < 1000000,
    D = is_list(os:getpid()),
    {A, B, C, D}.

%% E6.2 (Task 2): the LIVE receive/BIF timer family (DIVERGENCE entry 5's
%% residual + the 8 timer BIF rows). Every case returns a term that is
%% DETERMINISTIC on both VMs — independent of the real vs virtual elapsed time —
%% so the differential is timing-free (the receive-after determinism rule; a
%% timing-dependent remaining-ms is law-proven in proc.zig, never in the corpus).

%% recv_after: a message-clause-free `receive after N` fires the after-clause.
%% Returns `timed_out` regardless of N (the after-clause VALUE is deterministic;
%% the DELAY is not observed). No message clause, so a stray message in the shared
%% oracle mailbox can never be matched. Exercises `wait_timeout` finite arm + fire.
recv_after(N) ->
    receive
    after N ->
        timed_out
    end.

%% send_after_self: send_after delivers `hello` to self after N ms; a SELECTIVE
%% receive on `hello` (never a stray oracle-mailbox message) returns it. Returns
%% `hello`. Exercises send_after arm + fire + delivery.
send_after_self(N) ->
    _ = erlang:send_after(N, self(), hello),
    receive hello -> hello end.

%% start_timer_self: start_timer delivers `{timeout, TRef, tick}` to self; the
%% selective receive matches the bound TRef and returns `tick`. Exercises
%% start_timer's 3-tuple shape + the TRef round-trip through the message.
start_timer_self(N) ->
    R = erlang:start_timer(N, self(), tick),
    receive {timeout, R, X} -> X end.

%% cancel_fired: cancel_timer on an ALREADY-FIRED timer returns `false` on both
%% VMs (deterministic — no remaining time to report). Exercises the cancel-race
%% totality's fired arm.
cancel_fired(N) ->
    R = erlang:start_timer(N, self(), tick),
    receive {timeout, R, _} -> ok end,
    erlang:cancel_timer(R).

%% read_cancelled: read_timer on a CANCELLED timer returns `false` on both VMs.
%% The timer is armed far in the future and cancelled before it can fire (the
%% remaining ms cancel returns is DISCARDED — it is timing-dependent). Returns
%% `false`. Exercises the arm/cancel round-trip + read-after-cancel.
read_cancelled(N) ->
    R = erlang:start_timer(1000000 + N, self(), x),
    _ = erlang:cancel_timer(R),
    erlang:read_timer(R).

%% E6.5 (Task 5): the system introspection family (statistics/system_info/
%% system_flag/system_profile/system_monitor/scheduler_wall_time/bump_reductions).
%% Every case returns a DETERMINISTIC term on both VMs — the counter/setting
%% VALUES are host-nondeterministic (reduction/clock counters) or pid-repr-specific
%% (the monitor pid), so only the guarantees erts makes are observed: integer type,
%% reduction monotonicity, and the set/get round-trips. Each case restores whatever
%% it set (backtrace_depth / profiler / monitor / scheduler_wall_time), so the
%% shared oracle node is left unchanged.

%% stat_props: statistics counters are integers and reductions is monotone.
%% {true,true,true,true} on both VMs. Exercises statistics/1 (the counter subset).
stat_props(_) ->
    {R1, S1} = erlang:statistics(reductions),
    {R2, _}  = erlang:statistics(reductions),
    A = is_integer(R1) andalso is_integer(S1) andalso R2 >= R1,
    {RtT, RtD} = erlang:statistics(runtime),
    B = is_integer(RtT) andalso is_integer(RtD),
    {WcT, WcD} = erlang:statistics(wall_clock),
    C = is_integer(WcT) andalso is_integer(WcD),
    D = is_integer(erlang:statistics(run_queue)),
    {A, B, C, D}.

%% sysinfo_const: the VERSION-INDEPENDENT system_info constants — never a release
%% or ERTS-version item (W-11: the host is OTP-28, the target OTP-30). Returns
%% {8, 8, "BEAM", little, true} on both VMs. Exercises system_info/1.
sysinfo_const(_) ->
    {erlang:system_info(wordsize),
     erlang:system_info({wordsize, internal}),
     erlang:system_info(machine),
     erlang:system_info(endian),
     erlang:system_info(smp_support)}.

%% flag_roundtrip: system_flag(backtrace_depth, _) round-trips the depth int; the
%% default VALUE is never asserted (only New==Set + is_integer(Old)). {true,true}.
flag_roundtrip(_) ->
    Old = erlang:system_flag(backtrace_depth, 12),
    New = erlang:system_flag(backtrace_depth, Old),
    {is_integer(Old), New =:= 12}.

%% bump_red: bump_reductions/1 returns `true` and raises the reduction count.
%% {true,true}. Exercises bump_reductions/1 + statistics(reductions) monotonicity.
bump_red(_) ->
    {R1, _} = erlang:statistics(reductions),
    B = erlang:bump_reductions(10000),
    {R2, _} = erlang:statistics(reductions),
    {B, R2 >= R1}.

%% profile_roundtrip: system_profile/0,2 round-trip the profiler setting; an
%% `undefined` profiler leaves profiling disabled (undefined on both VMs).
%% {true,true,true}.
profile_roundtrip(_) ->
    A = erlang:system_profile() =:= undefined,
    Prev = erlang:system_profile(undefined, [runnable_procs]),
    B = Prev =:= undefined,
    C = erlang:system_profile() =:= undefined,
    {A, B, C}.

%% monitor_roundtrip: erts_internal:system_monitor legacy get/set round-trip. The
%% set stores {self(), Opts}; the getter's pid is compared REPRESENTATION-FREE
%% (=:= self()), never printed. An `undefined` MonitorPid clears it. {true,true,true,true}.
monitor_roundtrip(_) ->
    A = erts_internal:system_monitor(legacy) =:= undefined,
    Prev = erts_internal:system_monitor(legacy, self(), [{long_gc, 100}]),
    B = Prev =:= undefined,
    {P, O} = erts_internal:system_monitor(legacy),
    C = (P =:= self()) andalso (O =:= [{long_gc, 100}]),
    _ = erts_internal:system_monitor(legacy, undefined, []),
    D = erts_internal:system_monitor(legacy) =:= undefined,
    {A, B, C, D}.

%% swt_roundtrip: erts_internal:scheduler_wall_time/1 round-trips the enable flag
%% (a boolean); left disabled. {true,true}.
swt_roundtrip(_) ->
    Old = erts_internal:scheduler_wall_time(true),
    New = erts_internal:scheduler_wall_time(Old),
    _ = erts_internal:scheduler_wall_time(false),
    {is_boolean(Old), is_boolean(New)}.

%% E6.6 (Task 6): the dirty-TAGGED PURE rows with a RETURN-VALUE observable. Each
%% is a pure total function; the dirty tag is a scheduling hint (dirty is
%% denote-invariant). Every result is DETERMINISTIC and byte-identical on both
%% VMs. float_to_binary/1 is asserted only via its ROUND-TRIP (the default text
%% is shortest round-trip, not fixed — the float_to_list/1 discipline);
%% float_to_binary/2 {decimals,D} IS a fixed byte form. Returns N on both VMs.
%% (display/1 + display_string/2 are the DIRECT-fd verbs: byte-faithful — display/1
%% is the %T writer, byte-verified against the host — but their stdout side-effect
%% is not attributable per-case in the oracle printer stream, which emits the
%% RETURN term; they ride the io.zig Zig law instead, the float_to_list/1
%% discipline. DIVERGENCE 120.)
dirty_pure(N) ->
    {a,x,b,c} = erlang:insert_element(2, {a,b,c}, x),
    {a,b,c,z} = erlang:insert_element(4, {a,b,c}, z),
    {a,c}     = erlang:delete_element(2, {a,b,c}),
    2.5 = erlang:binary_to_float(erlang:float_to_binary(2.5)),
    1.5 = erlang:binary_to_float(erlang:float_to_binary(1.5)),
    <<"2.50">> = erlang:float_to_binary(2.5, [{decimals, 2}]),
    3.25 = erlang:binary_to_float(<<"3.25">>),
    N.

%% E6.6 (Task 6): the OBSERVABLE dirty-scheduler erts_internal rows.
%% is_process_executing_dirty/1 -> false (no dirty runtime); the restricted
%% code-check entries raise error:notsup on BOTH VMs (the process/context
%% restriction dominates, host-verified arg-independent); perf_counter_unit/0 is
%% property-folded (integer & positive — the raw value is host-coupled, W-11).
%% Returns N on both VMs.
dirty_rows(N) ->
    false = erts_internal:is_process_executing_dirty(self()),
    ok = try erts_internal:check_dirty_process_code(self(), some_mod)
         catch error:notsup -> ok end,
    ok = try erts_internal:dirty_process_handle_signals(self())
         catch error:notsup -> ok end,
    U = erts_internal:perf_counter_unit(),
    true = is_integer(U) andalso U > 0,
    N.
%% E6.7 (Task 7): the port-representation surface (deferred-E6-portrepr). All
%% observations are representation-FREE (a name STRING, membership, =:= self()/id
%% type) or a rejection (the control-verb `badarg` return), so the case returns
%% its int N byte-identically on both VMs despite port-VALUE representation
%% differences. See DIVERGENCE entry 124.
port_verbs(N) ->
    P = op_open({spawn, "cat"}, [binary]),
    Self = self(),
    {name, "cat"} = erts_internal:port_info(P, name),
    true = is_list(erts_internal:port_info(P)),
    true = lists:member({name, "cat"}, erts_internal:port_info(P)),
    true = (element(2, erts_internal:port_info(P, connected)) =:= Self),
    true = is_integer(element(2, erts_internal:port_info(P, id))),
    true = lists:member(P, erlang:ports()),
    %% the RAW erts_internal control verbs RETURN the atom `badarg` (no driver):
    badarg = erts_internal:port_call(P, 0, []),
    badarg = erts_internal:port_control(P, 0, []),
    _ = op_close(P),
    undefined = erts_internal:port_info(P),
    undefined = erts_internal:port_info(P, name),
    N.

%% port_conn: reassign the port's connected (owner) process to a spawned child,
%% observed representation-free via port_info(connected) =:= Pid.
port_conn(N) ->
    P = op_open({spawn, "cat"}, [binary]),
    Parent = self(),
    Pid = spawn(corpus_seed, port_conn_child, [Parent]),
    receive {ready, Pid} -> ok end,
    true = erts_internal:port_connect(P, Pid),
    true = (element(2, erts_internal:port_info(P, connected)) =:= Pid),
    Pid ! stop,
    _ = op_close(P),
    N.
port_conn_child(Parent) -> Parent ! {ready, self()}, receive stop -> ok end.

%% E6.7 (Task 7): ETS ownership — give_away/3 + setopts/2 (heir). The heir
%% receives {'ETS-TRANSFER',Tab,From,{gift,N}} and echoes N back; ownership and
%% heir are observed representation-free via ets:info(T, owner|heir) =:= Pid.
%% Returns N on both VMs. See DIVERGENCE entry 124.
ets_giveaway(N) ->
    T = ets:new(gt, [public]),
    Self = self(),
    true = (ets:info(T, owner) =:= Self),
    Heir = spawn(corpus_seed, ets_heir, [Self]),
    receive {ready, Heir} -> ok end,
    true = ets:setopts(T, {heir, Heir, hd}),
    true = (ets:info(T, heir) =:= Heir),
    true = ets:give_away(T, Heir, {gift, N}),
    receive {got, V} -> V end.
ets_heir(Parent) ->
    Parent ! {ready, self()},
    receive {'ETS-TRANSFER', _Tab, _From, {gift, V}} -> Parent ! {got, V} end.

%% ets_whereis: ets:whereis(Name) returns the Tid; it round-trips through lookup
%% (representation-free — the Tid is never printed). Returns N on both VMs.
ets_whereis(N) ->
    ets:new(wt, [named_table, public]),
    ets:insert(wt, {k, N}),
    T = ets:whereis(wt),
    [{k, V}] = ets:lookup(T, k),
    V.

%% E7.3 (DIVERGENCE 143): shared ETS — a table one process creates and fills is
%% visible to ANOTHER process. The parent creates a named public table and
%% inserts {k,N}; a spawned child looks up the SAME named table (resolved by its
%% global atom, no Tid passed) and echoes N back. Impossible before E7.3 (ETS
%% was per-Machine — DIVERGENCE 124); now the child's lookup crosses into the
%% shared table space and copies the object into its own heap. Returns N on both
%% VMs, representation-free (only the int N is observed).
ets_shared(N) ->
    ets:new(esh, [named_table, public]),
    ets:insert(esh, {k, N}),
    Self = self(),
    _Child = spawn(corpus_seed, ets_shared_child, [Self]),
    receive {got, V} -> V end.
ets_shared_child(Parent) ->
    [{k, V}] = ets:lookup(esh, k),
    Parent ! {got, V}.

%% E7.5 (DIVERGENCE 154): erlang:hibernate/3 MFA-reentry, end-to-end. A worker
%% loops accumulating an int; on `{add, X}` it HIBERNATES — discarding its call
%% stack and re-entering hib_loop/2 at the new accumulator when the next message
%% arrives. The mailbox survives hibernate, so the queued `{get, From}` (sent
%% before the worker re-enters) is found by the re-entered `receive` and the
%% accumulator N is echoed back. Proves: (1) reentry at M:F/A with the new args,
%% (2) the mailbox is preserved across hibernate. Returns N on both VMs
%% (representation-free — only the int N is observed, no pid/ref VALUE).
phibernate(N) ->
    Parent = self(),
    P = spawn(corpus_seed, hib_loop, [Parent, 0]),
    P ! {add, N},          %% triggers hibernate: re-enter hib_loop(Parent, N)
    P ! {get, Parent},     %% queued; the re-entered receive finds it
    receive {sum, S} -> S end.
hib_loop(Parent, Acc) ->
    receive
        {add, X} -> erlang:hibernate(corpus_seed, hib_loop, [Parent, Acc + X]);
        {get, From} -> From ! {sum, Acc}
    end.
%% E7.6 (DIVERGENCE 158): the sequential-trace TOKEN round-trip. Each component
%% is set then read back; the setter returns the PREVIOUS value; the token is
%% then CLEARED and every info read denotes [] (the empty-token law). Every
%% observation is version-stable and schedule-independent, so both VMs fold to N
%% byte-identically. (serial is deliberately NOT observed — it auto-bumps on
%% seq-traced signals, schedule-coupled.) The final clear leaves no token
%% lingering into the result print.
seq_trace_surface(N) ->
    false = erlang:seq_trace(send, true),
    {send, true} = erlang:seq_trace_info(send),
    true = erlang:seq_trace(send, false),
    {send, false} = erlang:seq_trace_info(send),
    false = erlang:seq_trace('receive', true),
    {'receive', true} = erlang:seq_trace_info('receive'),
    false = erlang:seq_trace(print, true),
    {print, true} = erlang:seq_trace_info(print),
    _ = erlang:seq_trace(label, N),
    {label, N} = erlang:seq_trace_info(label),
    _ = erlang:seq_trace(sequential_trace_token, []),
    [] = erlang:seq_trace_info(label),
    N.

%% E7.6: the dt_* DYNAMIC-TRACE tag family on a NON-dtrace build (both VMs) —
%% the getters are the constant `undefined`, the spread/restore token pair the
%% constant `true`, and prepend/append are the identity on their argument. Folds
%% to N on both VMs.
dt_surface(N) ->
    undefined = erlang:dt_get_tag(),
    undefined = erlang:dt_get_tag_data(),
    undefined = erlang:dt_put_tag(<<"x">>),
    undefined = erlang:dt_get_tag(),
    true = erlang:dt_spread_tag(true),
    true = erlang:dt_restore_tag(true),
    N = erlang:dt_prepend_vm_tag_data(N),
    N = erlang:dt_append_vm_tag_data(N),
    N.

%% E7.6: the no-tracer / empty-trace answers. seq_trace_print/1,2 return `false`
%% with no system tracer; trace_info/2 returns the untraced defaults {flags,[]}
%% and {tracer,[]}. Folds to N on both VMs.
trace_query(N) ->
    false = erlang:seq_trace_print("x"),
    false = erlang:seq_trace_print(0, "y"),
    {flags, []} = erlang:trace_info(self(), flags),
    {tracer, []} = erlang:trace_info(self(), tracer),
    N.

%% E7.9: hosted `re:` engine corpus probes. Each returns only the input int, so
%% compiled-pattern references and binary/list formatting differences never
%% leak into the byte comparison; the BIF observations themselves must still
%% match OTP exactly.
re_simple(N) ->
    {match, [{0, 6}, {3, 3}]} =
        re:run(<<"abc123">>, <<"[a-z]+([0-9]+)">>),
    N.

re_global(N) ->
    {match, [[<<"b">>], [<<"b">>]]} =
        re:run(<<"abcabc">>, <<"a(b)c">>,
               [global, {capture, all_but_first, binary}]),
    N.

re_import_rt(N) ->
    {ok, Exported} = re:compile(<<"ab+c">>, [export]),
    Pattern = re:import(Exported),
    {namelist, []} = re:inspect(Pattern, namelist),
    {match, [{2, 4}]} =
        re:run(<<"xxabbc">>, Pattern, [{capture, first, index}]),
    N.


%% dist_channel_live: E9.1 — successful setnode/create_dist_channel path.
%% registers net_kernel, sets node, and promotes a pending connection.
%% returns the node atom.
my_dummy_net_kernel() ->
    true = register(net_kernel, self()),
    receive wait -> ok end.

my_dist_ctrl(Parent) ->
    try
        %% 17230663572 = 2^34 + 3 * 2^24 + 33554432 + 16777216 + 20
        %% wait: 17230663572 = 17179869184 (2^34) + 50331648 (3 * 2^24) + 462740 (not right)
        %% Let's just use doubler(34) + doubler(25) + doubler(24) + 20
        %% 2^34 = 17179869184
        %% 2^25 = 33554432
        %% 2^24 = 16777216
        %% 17179869184 + 33554432 + 16777216 + 20 = 17230200852 != 17230663572
        %% Let's just do a loop:
        DFlags = build_dflags(17230, 1000000) + 663572,
        _C = erts_internal:new_connection('live_node@host'),
        {ok, _DHandle} = erts_internal:create_dist_channel('live_node@host', self(), {DFlags, 4}),
        Parent ! {self(), ok}
    catch E:R ->
        Parent ! {self(), {error, E, R}}
    end,
    receive wait -> ok end.

%% e21-t2 (DIVERGENCE 490): `node(self()) =:= node()` — the local-node identity
%% under BOTH operand orders. `node/0` compiles to a guard `bif0` that TRAPS
%% (get_dist_node); its resolved value must land in the opcode's real Dst, which
%% is NON-x0 when the other operand (`node(self())`, a direct bif1) is already
%% live in x0. The pre-fix VM delivered the trap result to x0 unconditionally, so
%% `node(self()) =:= node()` observed the nil placeholder ([]) and returned false
%% (proc_lib:proc_info/2's first guard — the OTP-behaviour boot path). Folds both
%% orders so the fix is order-symmetric; returns N iff both hold. EQ vs OTP-30.
node_self_eq(N) ->
    A = (node(self()) =:= node()),
    B = (node() =:= node(self())),
    case A andalso B of true -> N; _ -> -1 end.

%% e21-t2b (DIVERGENCE 510): a SPAWNED child that sends a COMPOUND LITERAL
%% ({tag, 99}) back to the parent. Pre-fix zigvm borrowed the parent's literal
%% table across ctxs, so the child resolved that boxed literal against its OWN
%% heap — an OOB panic (bigParts/listHead) or a mis-tagged tuple that never
%% matched {tag,X} (receive deadlock). Post-fix the child owns a rebased table.
%% The tag ADDS N so N flows through the sent literal payload; returns N iff the
%% received tuple matches exactly. EQ vs OTP-30.
lit_sender(P) -> P ! {tag, 99}.
child_lit_send(N) ->
    P = self(),
    spawn(corpus_seed, lit_sender, [P]),
    receive {tag, X} -> X + N - 99 end.

%% e21-t2b (DIVERGENCE 490-amend): process_info/2 DISPATCH. A compiled
%% process_info(self(), registered_name) call previously resolved `undef` (the
%% row is ledger-deferred and was absent from the call_ext resolver). Wired via
%% the dispatch-needed-deferred carve-out, it now runs the real BIF: an
%% UNREGISTERED process denotes the bare atom [] (erts' special case). Returns N
%% iff the byte-total item answers []. EQ vs OTP-30.
pinfo_regname(N) ->
    case erlang:process_info(self(), registered_name) of
        [] -> N;
        _  -> -1
    end.

build_dflags(0, _) -> 0;
build_dflags(N, X) when N > 0 -> X + build_dflags(N - 1, X).

dist_channel_live(N) ->
    %% Register a dummy net_kernel
    NK = spawn_link(corpus_seed, my_dummy_net_kernel, []),
    receive after 10 -> ok end,
    try
        true = erlang:setnode('my_node@host', 4),
        Parent = self(),
        Ctrl = spawn_link(corpus_seed, my_dist_ctrl, [Parent]),
        receive
            {Ctrl, ok} -> 
                unlink(NK), exit(NK, kill),
                unlink(Ctrl), exit(Ctrl, kill),
                N;
            {Ctrl, {error, E, R}} ->
                {caught, E, R}
        end
    catch E2:R2 ->
        {outer_caught, E2, R2}
    end.


