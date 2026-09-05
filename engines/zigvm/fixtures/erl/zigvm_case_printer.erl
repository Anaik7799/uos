%% zigvm_case_printer — the oracle-side differential driver (E0.6).
%%
%% DIVISION OF LABOR (OTP30_PARITY_PLAN.md §3): this is an Erlang FIXTURE, not
%% harness logic. The OCaml harness compiles it with the pinned-or-host erlc and
%% runs it on the oracle:
%%
%%     erl -noshell -pa <ebin> -s zigvm_case_printer main -s init stop
%%
%% For each corpus case it prints exactly one line
%%
%%     CASE <fn> <printed-term>
%%
%% using `~w` — the canonical, space-free term writer, which matches zigvm's
%% diag.formatValue term syntax byte-for-byte ([3,2,1], {ok,1,[2,3]}, #{...}).
%% `~p` is deliberately NOT used: it inserts spaces/newlines for pretty-printing
%% and would create spurious DIVERGENT rows against the VM's compact writer.
%%
%% Zig side: the harness invokes `zigvm run corpus_seed.beam <fn> [ints]`
%% directly (the CLI already prints the denoted result), so the differential
%% comparison for each RUNNABLE case is: this driver's `CASE <fn> X` term vs the
%% VM's stdout for the same fn+args. If diag.formatValue and ~w ever disagree on
%% a case, that is a REAL DIVERGENT to record — never normalized away.
%%
%% The list is split into two groups (see corpus_seed.erl for why):
%%   runnable_cases/0 — driven on BOTH VMs (corpus_seed exports, int-args).
%%   oracle_only_cases/0 — M2/M4/term-order/atom/exact-eq domains the E0 CLI
%%     convention cannot express; printed here for the oracle value, recorded
%%     UNTESTED(calling-convention) on the zigvm side by the harness.
%% Every printed line is `CASE <fn> <term>` regardless of group; the harness
%% decides runnability from its own case table, so the stream stays uniform.
-module(zigvm_case_printer).
-export([main/0, runnable_names/0]).

%% {Fn, Args} — invoked via apply(corpus_seed, Fn, Args). Args are exactly what
%% the harness passes to `zigvm run` (a single list arg is spread as int-args).
runnable_cases() ->
    [ {sum_list,      [[1, 2, 3, 4, 5]]},
      {rev_list,      [[1, 2, 3]]},
      {len_list,      [[1, 2, 3, 4]]},
      {range,         [5]},
      {factsum,       [10]},
      {arith,         []},
      {bignum,        []},
      {big_neg,       [7]},
      {doubler,       [21]},
      {add_pair,      [40, 2]},
      {nth3,          [[7, 8, 9, 10]]},
      {plus_minus,    [100]},
      {countdown_sum, [5]},
      %% E1 ISA-totality cases (tuples/maps/guards/try/funs/select)
      {tup_swap,      [1, 2]},
      {tup_mid,       [7, 8, 9]},
      {cmp_ge,        [5, 3]},
      {is_int_test,   [42]},
      {trycatch,      [1]},
      {try_class,     [5]},   %% E3.10: {error,badarith} via try..catch C:R (class observed)
      {stk_line,      [5]},   %% E3.11: cooked-stacktrace head-frame line (DIVERGENCE 2b)
      {closure,       [5]},
      {map_get1,      [10, 20]},
      {tagged,        [99]},
      {sel,           [2]},
      %% E3.4 bit-syntax construction<->matching round-trip cases
      {bs_int16,      [300]},
      {bs_int_le,     [300]},
      {bs_two_ints,   [200, 55]},
      {bs_signed,     [90]},
      {bs_utf8_rt,    [64]},
      {bs_utf16_rt,   [70000]},
      {bs_tail,       [11, 22]},
      {bs_append,     [3, 4]},
      %% E3.12: static multi-module dispatch (call_ext -> BIF/apply)
      {err_catch,     [42]},   %% erlang:error/1 caught by class error
      {throw_catch,   [7]},    %% throw/1 caught by class throw
      {exit_catch,    [9]},    %% exit/1 (raise form) caught by class exit
      {pdict,         [55]},   %% put/2 + get/1 + erase/1 round-trip
      {apply_add,     [40, 2]}, %% apply(erlang,'+',[40,2]) == 42
      %% E3.18: E2 fast-follow sweep (predicates / min-max / checksums /
      %% calendar / ets-core)
      {pred_check,    [42]},        %% is_integer/is_number/is_atom guard
      {minmax,        [3, 8]},      %% min*1000+max == 3008
      {crc_of,        [123456]},    %% erlang:crc32(integer_to_list/1)
      {adler_of,      [123456]},    %% erlang:adler32(integer_to_list/1)
      {cal_rt,        [1000000000]},%% posixtime<->universaltime round-trip
      {ets_take_v,    [77]},        %% ets:new/insert/take round-trip
      %% E3.12b: cross-module dispatch into corpus_dep (linked via `--pa`)
      {xadd,          [40, 2]},     %% corpus_dep:add(40,2)+helper(40) == 163
      {xchain,        [5]},         %% corpus_dep:chain(5) == 46
      %% E3.13: fun/module introspection (is_builtin/3, function_exported/3)
      {builtin_check, [0]},         %% {is_builtin(erlang,abs,1), is_builtin(lists,foldl,3)} == {true,false}
      {fnexp_check,   [0]},         %% {function_exported(corpus_seed,sum_list,1), .../nope,0} == {true,false}
      {dbg_sup,       [0]},         %% E7.7: erl_debugger:supported() == false (both VMs)
      %% E3.15: ets match/select family (matchspec-term compiler)
      {ets_select_v,   [7]},        %% sum of '$2' where key>2 == 2*7+7 == 21
      {ets_selcount_v, [2]},        %% count of keys>2 among 1..5 == 3
      {ets_matchspec_v,[42]},       %% match_spec_test on {5,X} body '$2' == 42
      {ets_selchunk_v, [3]},        %% continuation select sum == 4*3+10 == 22
      %% E3.16: ets duplicate_bag exact-duplicate retention + delete-all-copies
      {ets_dbag_v,     [5]},        %% 3 copies retained, delete_object clears all == 30
      %% E5.9: ets:rename/2 — rename a named table, reach it by the new name == 88
      {ets_rename_v,   [88]},
      %% E3.17: big Unicode tables (S9) — characters_to_binary/list round-trip
      %% over ASCII/Latin-1/Greek/supplementary plane; sum == 65+233+945+66560
      {uni_rt,         [[65, 233, 945, 66560]]}, %% == 67803
      %% E4.1: process-effect BIFs via the scheduler-as-driver. Each returns its
      %% input int (identity matched on wildcards / bools), so the CASE stream is
      %% byte-identical on both VMs despite pid-value differences.
      {pspawn,         [7]},   %% spawn/3 + send + receive round-trip == 7
      {preg,           [7]},   %% register/whereis/unregister bijection == 7
      {palive,         [7]},   %% is_process_alive(self()) == true -> 7
      %% e4-registered0: register/2 + registered/0 registry-backed, SET-membership
      {pregall,        [7]},   %% register a name, registered() contains it == 7
      {pmon,           [7]},   %% monitor + 'DOWN' round-trip == 7
      {plink,          [7]},   %% trap_exit + spawn_link + 'EXIT' == 7
      %% E21.1 (DIVERGENCE 450): spawn/1 + spawn_link/1 of a FUN. (These were
      %% added to corpus_seed + the harness case table in e21-t1 but omitted from
      %% this oracle-side list — restored in e21-t2 so the pinned-OTP-30 corpus
      %% cross-check is total, SC-8.2.)
      {pspawn_fun,     [7]},   %% spawn(fun) closure env-capture + send/receive == 7
      {plink_fun,      [7]},   %% spawn_link(fun) + trap_exit/'EXIT' == 7
      %% E4.2: module metadata via M:module_info/0,1 (erlang:get_module_info)
      {mi_md5,         [0]},   %% module_info(md5) == 16-byte checksum binary
      {mi_mod,         [0]},   %% module_info(module) == corpus_seed
      %% E4.2b: erts_internal:beamfile_chunk/2 over a synthetic IFF container
      {bfc,            [0]},   %% found "Atom" chunk payload == <<1,2,3,4>>
      {bfc_absent,     [0]},   %% absent "AtU8" chunk == undefined
      %% E6.8: strict FORM-SIZE reader (DIVERGENCE 108 discharge)
      {bfc_bigform,    [0]},   %% form_size too big + truncated tail == undefined
      {bfc_trailing,   [0]},   %% trailing-after-form ignored == <<1,2,3,4>>}
      %% E4.4: prim_file:/file: native-name codec (all five bif.tab rows) over an
      %% A/é/α name; folds both codec round-trips (+NUL), the encoding atom, and
      %% the translatable flag into one int == 1102486 on both VMs (utf8 host).
      {nne_rt,         [[65, 233, 945]]},
      %% E4.6: the io / group-leader protocol — group_leader() =/= self() (BOOL).
      {gl_not_self,    [7]},   %% distinct GL (OTP shell / zigvm standard_io) == 7
      %% E5.4: the live os-port driver — both VMs spawn a real `cat`. Results are
      %% the echoed / stored byte (an int), never a Port VALUE, so byte-identical.
      {port_echo,      [65]},  %% cat echoes <<65>> back -> 65
      {port_data_rt,   [42]}, %% port_set_data(42)/port_get_data -> 42
      %% E5.5 (Task 5): the alias-signal model — alias delivery + post-unalias
      %% drop + async is_process_alive/2 reply == 7; monitor-alias DOWN-retire == 3.
      {palias,         [7]},
      {malias,         [3]},
      %% E5.2c: the RELOAD half's PURE row — beamfile_module_md5/1 over a real
      %% embedded beam blob. Both VMs return the SAME 16-byte checksum. BEFORE
      %% code_q (which retires corpus_seed, blocking later corpus_seed calls).
      {bfmd5,          [0]},   %% <<221,136,43,112,153,9,230,63,...>>
      %% e5-dispatch-codeidx (DIVERGENCE 81): a LIVE reload — prepare_loading/2 +
      %% finish_loading/1 over the embedded zmini blob, then CALL zmini:z() through
      %% the runtime code table. Returns N (== 0 + N). BEFORE code_q (which retires
      %% corpus_seed, blocking later corpus_seed calls).
      {reload_call,    [5]},
      %% E7.2 (DIVERGENCE 147): the on_load STAGING trio over an embedded on_load
      %% beam blob — prepare -> has_prepared -> finish {on_load,[Mod]} ->
      %% call_on_load_function -> finish_after_on_load -> z(). Returns 42 + N.
      {onload_call,    [5]},
      %% E6.3 (DIVERGENCE 108): the purger/collector PROCESS restriction — a direct
      %% (non-purger) call raises error:notsup on both VMs, folded to N.
      {purge_notsup,   [5]},
      {litarea_notsup, [3]},
      %% E6.4 (DIVERGENCE 112): the process-suspension + system-task family —
      %% suspend/resume counting monoid (balanced -> true), is_system_process
      %% (normal proc -> false), garbage_collect (-> true), system_check
      %% (schedulers -> ok); every call asserted, folds to N on both VMs.
      {suspend_fam,    [4]},
      %% E5.2b: the file-based code-server QUERY BIFs (check_old_code/delete_module)
      %% over the mutable two-version code table. MUST be LAST: code_q retires
      %% corpus_seed's own current version on the shared oracle node.
      %% E5.6 (Task 6): the async spawn/request protocol — spawn_request/4 +
      %% spawn_request_abandon/1 (reply carries the minted ReqId; abandon→false
      %% after the reply / on a foreign ref) == 9; erts_internal:process_flag/3
      %% save_calls (self old-value + cross-process async ref) == 5.
      {sreq,           [9]},
      {pf3,            [5]},
      %% E8.2b: non-distributed nodes/1,2 observer subset. Folds to N after
      %% asserting known/this vs connected/visible/hidden and the option map.
      %% Runs BEFORE fpid, which deliberately teaches the oracle about a foreign
      %% node name and would expand nodes(known).
      {nodes_opts,     [6]},
      %% E8.2c: no-carrier dist local observers. Runs after nodes_opts because
      %% it decodes a foreign pid, and before fpid's broader foreign identity case.
      {dist_local_obs, [8]},
      %% E8.2e: pinned OTP30 no-carrier DFLAG record.
      {dflags_obs,     [6]},
      %% E8.2d: no-carrier monitor_node/2,3 observer subset.
      {monitor_node_obs, [4]},
      %% E8.2f: erts_debug:dist_ext_to_term/2 debug dist-external decoder.
      {dist_ext_decode, [5]},
      %% E8.2g: no-carrier dist control-data rejection surface.
      {dist_ctrl_nohandle, [6]},
      %% E8.2i: no-carrier remote spawn request direct-BIF surface.
      {dist_spawn_no_conn, [10]},
      %% E8.2j: no-socket pending dist connection-id surface.
      {dist_pending_conn, [11]},
      {dist_channel_live, [13]},
      %% E8.2k: no-carrier channel-start rejection surface.
      {dist_channel_start_no_carrier, [12]},
      %% E8.2h: no-carrier exit_signal/2,3 identity and option surface.
      {exit_signal_obs, [9]},
      %% E5.7 (Task 7): external (foreign-node) pid/port/ref TERMS via ETF —
      %% binary_to_term of foreign NEW_PID_EXT/V4_PORT_EXT/NEWER_REFERENCE_EXT,
      %% node/1 == the foreign atom, byte-identical term_to_binary round-trip.
      {fpid,           [7]},
      %% E5.3 (Task 3): the GL SETTER pair erts_internal:group_leader/2,3 —
      %% child retargeted to the parent's GL, reports group_leader/0 =:= self().
      {glset,          [7]},
      %% E5.8b (Task 8b): the time/OS-clock family + os env, PROPERTY-folded to
      %% {true,true,true,true} on both VMs (no raw clock VALUE printed).
      {tclock,         [0]},
      {tosenv,         [0]},
      %% E6.2 (Task 2): the LIVE receive/BIF timer family. Deterministic results:
      %% recv_after -> timed_out; send_after_self -> hello; start_timer_self -> tick;
      %% cancel_fired -> false (a fired timer); read_cancelled -> false. BEFORE
      %% code_q (which retires corpus_seed, blocking later corpus_seed calls).
      {recv_after,     [5]},
      {send_after_self, [1]},
      {start_timer_self, [1]},
      {cancel_fired,   [1]},
      {read_cancelled, [1]},
      %% E6.5 (Task 5): the system introspection family, PROPERTY-folded to
      %% deterministic boolean tuples (counters/settings are host-nondeterministic
      %% or pid-repr-specific, so only monotonicity/type/round-trip is observed).
      %% stat_props -> {true,true,true,true}; sysinfo_const -> {8,8,"BEAM",little,true}
      %% (version-INDEPENDENT); flag_roundtrip -> {true,true}; bump_red -> {true,true};
      %% profile_roundtrip -> {true,true,true}; monitor_roundtrip -> {true,true,true,true};
      %% swt_roundtrip -> {true,true}. Every case restores what it set. BEFORE code_q.
      {stat_props,     [0]},
      {sysinfo_const,  [0]},
      {flag_roundtrip, [0]},
      {bump_red,       [0]},
      {profile_roundtrip, [0]},
      {monitor_roundtrip, [0]},
      {swt_roundtrip,  [0]},
      %% E6.6 (Task 6): the dirty-scheduler family — dirty_pure (the dirty-TAGGED
      %% pure rows: insert/delete_element, float<->binary, display/1 + display_string
      %% to stdout) and dirty_rows (the observable erts_internal rows). Each -> N.
      {dirty_pure,     [5]},
      {dirty_rows,     [3]},
      %% E6.7 (Task 7): the multi-process ETS-ownership + port-representation
      %% surface. port_verbs -> 7, port_conn -> 9, ets_giveaway -> 42,
      %% ets_whereis -> 5 (representation-FREE / rejection differentials). BEFORE
      %% code_q. See DIVERGENCE entry 124.
      {port_verbs,     [7]},
      {port_conn,      [9]},
      {ets_giveaway,   [42]},
      {ets_whereis,    [5]},
      %% E7.3 (DIVERGENCE 143): shared, Vm-owned ETS — cross-process table
      %% visibility (parent inserts, spawned child looks up the same named
      %% table). ets_shared -> 8. BEFORE code_q.
      {ets_shared,     [8]},
      %% E7.5 (DIVERGENCE 154): erlang:hibernate/3 MFA-reentry, end-to-end
      %% (worker hibernates on {add,N}, re-enters at hib_loop, echoes N).
      %% phibernate -> 7. BEFORE code_q.
      {phibernate,     [7]},
      %% E7.6 (DIVERGENCE 158): the honestly-observable tracing surface —
      %% seq_trace token round-trip (label + flags + clear), dt_* non-dtrace
      %% constants/identity, seq_trace_print / trace_info empty-trace answers.
      %% Each folds to its int on both VMs. BEFORE code_q.
      {seq_trace_surface, [7]},
      {dt_surface,        [9]},
      {trace_query,       [5]},
      %% E7.9 (DIVERGENCE 165): hosted re engine — direct run/captures, global
      %% binary capture matrix, and compile(export)->import->inspect round-trip.
      {re_simple,         [11]},
      {re_global,         [13]},
      {re_import_rt,      [17]},
      %% e21-t2 (DIVERGENCE 490): node/0 bif-trap dst-delivery — node(self())=:=node()
      {node_self_eq,      [7]},
      %% e21-t2b (DIVERGENCE 510): spawned-child compound-literal send (OOB fix)
      {child_lit_send,    [8]},
      %% e21-t2b (DIVERGENCE 490-amend): process_info/2 dispatch — registered_name -> []
      {pinfo_regname,     [5]},
      %% E5.2b: MUST be LAST — code_q retires corpus_seed's own current version
      %% on the shared oracle node. {false,true,true,undefined}
      {code_q,         [0]} ].

%% The runnable case function names, exposed so a reader/tool can cross-check the
%% harness case table against the fixture without re-parsing this source.
runnable_names() -> [ F || {F, _} <- runnable_cases() ].

%% Oracle-only domain cases: computed inline (fixture code may build any term).
%% Names are namespaced with a `rich_` prefix so they never collide with a
%% corpus_seed export and are trivially recognizable as UNTESTED-on-zigvm.
oracle_only_cases() ->
    [ {rich_tuple,    {ok, 1, [2, 3]}},                                   %% M2
      {rich_map,      begin M = #{a => 1, b => 2},
                            {maps:get(a, M), maps:get(b, M)} end},        %% M4
      {rich_sort,     lists:sort([3, a, 1.0, {x}, [1], 2])},             %% total order
      {rich_atomcmp,  [apple < banana, zebra > apple]},                  %% atom compare
      {rich_exacteq,  {1 =:= 1.0, 1 == 1.0}},                            %% exact vs arith eq
      {rich_float,    5 + 0.0} ].                                        %% E1.12 FR: X+0.0 needs a LitT float literal (W-17) or a BIF, so it load-rejects on the E0 CLI — oracle-only

main() ->
    lists:foreach(fun({F, Args}) ->
                      V = apply(corpus_seed, F, Args),
                      io:format("CASE ~s ~w~n", [F, V])
                  end, runnable_cases()),
    lists:foreach(fun({F, V}) ->
                      io:format("CASE ~s ~w~n", [F, V])
                  end, oracle_only_cases()).
