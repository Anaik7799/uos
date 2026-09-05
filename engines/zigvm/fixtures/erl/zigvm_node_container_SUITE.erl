%% zigvm_node_container_SUITE — a PURE, LOCAL-ONLY subset of
%% erts/emulator/test/node_container_SUITE.erl, in the common_test SUITE shape
%% (`all/0` + `Case(Config)` funs) with NO common_test / test_server / peer-node
%% dependency. The REAL suite is dominated by DISTRIBUTED node containers:
%% external pids/ports/refs synthesized with erts_test_utils:mk_ext_* against a
%% live ?CT_PEER() peer node, plus internal-state reference-count auditing
%% (erts_debug:get_internal_state(node_and_dist_references), node_table_gc,
%% dist_link_refc, dist_monitor_refc, magic_ref, pid_wrap/port_wrap via
%% erts_debug:set_internal_state(next_pid/next_port), iter_max_procs) — ALL of
%% which need a second node, on-disk internal-state pokes, or spawning 10^6
%% processes, none of which exist on the zigvm CLI. Those are EXCLUDED.
%%
%% What SURVIVES is the semantic core the two VMs must agree on for LOCAL node
%% containers (this node is non-distributed: node() =:= nonode@nohost):
%%   * cmp  — the inter-type Erlang term order (number < atom < ref < pid <
%%            tuple < nil < cons < binary) with self()/make_ref() standing in
%%            for the local pid and ref, plus intra-type ORDER CONSISTENCY
%%            (a total order: irreflexive, antisymmetric, transitive) — WITHOUT
%%            asserting any concrete pid/ref VALUE (forbidden cross-VM).
%%   * ref_eq — a reference equals itself under == and =:=, distinct refs are
%%            distinct (identity/distinctness property, not a value).
%%   * the type guards is_pid/1, is_reference/1, is_port/1 discriminating the
%%            identity terms.
%%   * node/0 and node/1 on a local pid and a local ref (all nonode@nohost).
%%   * CONTAINER ROUND-TRIPS: pids/refs nested in tuples, maps (as both values
%%            AND keys), and lists survive construction/deconstruction and
%%            term_to_binary/binary_to_term (a within-VM round-trip identity —
%%            NOT a cross-VM byte assertion) with their identity intact.
%%   * SEND/RECEIVE preserving pid/ref identity: a spawned child's pid arrives
%%            distinct-and-is_pid, and a make_ref()-tagged selective receive
%%            picks exactly its reply.
%%
%% Discipline (mirrors zigvm_receive_SUITE): every case is self-contained +
%% deterministic; spawned children terminate by construction; every receive is
%% bounded (`after 1000`, so a bug is a false return, never a hang); the mailbox
%% is verified EMPTY before returning; and pure-value seeds (the atoms/numbers/
%% binaries used as ordering anchors) are routed through the exported ?MODULE:id/1
%% so constant folding cannot bypass the VM. self()/make_ref() are runtime BIFs
%% and are never foldable. NO lists:* is called (the standalone CLI does not
%% auto-load stdlib — local helpers only). A case returns the atom `true` on
%% success; the runner (zigvm_node_container_suite_runner) counts a case EQ only
%% when BOTH VMs' `Suite:Case([])` returns `true`.
-module(zigvm_node_container_SUITE).

-export([all/0,
         c_pid_identity/1, c_ref_identity/1, c_ref_eq/1,
         c_type_guards/1, c_cross_type_order/1, c_order_consistency/1,
         c_node_local/1, c_pid_in_tuple/1, c_ref_in_map/1,
         c_containers_in_list/1, c_nested_round_trip/1,
         c_send_recv_identity/1,
         %% exported spawned entry point (spawn/3 MFA) + id/1 fold-firewall.
         id/1, child/2]).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's node_container-suite spec case_names (ncases/1
%% lockstep).
all() ->
    [c_pid_identity, c_ref_identity, c_ref_eq,
     c_type_guards, c_cross_type_order, c_order_consistency,
     c_node_local, c_pid_in_tuple, c_ref_in_map,
     c_containers_in_list, c_nested_round_trip,
     c_send_recv_identity].

%% Identity through an exported call — the compiler cannot constant-fold across
%% it, so ordering-anchor literals genuinely travel through the VM.
id(X) -> X.

%% --- pid identity: self() is a stable pid, reflexively equal to itself -------
%% self() called twice in one process yields the same pid; a pid equals itself
%% under both == (arith) and =:= (exact); is_pid/1 accepts it.
c_pid_identity(_) ->
    P = self(),
    Q = self(),
    is_pid(P)
        andalso (P =:= Q)
        andalso (P == Q)
        andalso (P =:= P)
        andalso (not (P =/= Q))
        andalso (not (P /= Q)).

%% --- ref identity: make_ref/0 is a reference, reflexively equal, and fresh ---
%% One ref equals itself; two independently-created refs are distinct under
%% both =:= (so =/= holds) and == (so /= holds).
c_ref_identity(_) ->
    R = make_ref(),
    A = make_ref(),
    B = make_ref(),
    is_reference(R)
        andalso (R =:= R)
        andalso (R == R)
        andalso (A =/= B)
        andalso (A /= B)
        andalso (not (A =:= B))
        andalso (not (A == B)).

%% --- ref_eq (local analog of the suite's ref_eq): equality is exact ----------
%% A ref bound to a name is the SAME ref everywhere it is used (=:= and ==,
%% negations false); two fresh refs never compare equal. No VALUE is asserted —
%% only the equality/inequality relation, which both VMs must compute alike.
c_ref_eq(_) ->
    R = make_ref(),
    Same = R,
    S = make_ref(),
    (R =:= Same)
        andalso (R == Same)
        andalso (not (R =/= Same))
        andalso (Same =:= R)
        andalso (R =/= S)
        andalso (S =/= R)
        andalso (not (R =:= S)).

%% --- type guards: is_pid / is_reference / is_port discriminate the terms -----
%% Each guard accepts exactly its own identity type and rejects the others and
%% non-container terms. is_port(self()) is false on this port-free node.
c_type_guards(_) ->
    P = self(),
    R = make_ref(),
    is_pid(P)
        andalso (not is_pid(R))
        andalso (not is_pid(id(an_atom)))
        andalso is_reference(R)
        andalso (not is_reference(P))
        andalso (not is_reference(id(an_atom)))
        andalso (not is_port(P))
        andalso (not is_port(R))
        andalso is_atom(node()).

%% --- cmp (inter-type): the canonical Erlang term order across types ----------
%% number < atom < ref < pid < tuple < nil < cons < binary, with make_ref()/
%% self() as the local ref/pid. Every non-identity anchor is routed through
%% id/1 so the comparison is evaluated by the VM, not folded at compile time.
c_cross_type_order(_) ->
    R = make_ref(),
    P = self(),
    %% number < atom < ref
    (id(1) < R) andalso (id(1.3) < R) andalso (id(an_atom) < R)
        andalso (id((1 bsl 64)) < R)
        %% ref < pid
        andalso (R < P)
        andalso (id(1) < P) andalso (id(an_atom) < P)
        %% pid < tuple < nil < cons < binary
        andalso (P < id({a, tuple}))
        andalso (P < id([]))
        andalso (P < id([a | cons]))
        andalso (P < id(<<"a binary">>))
        %% and the ref sits below all of those too (transitive spot checks)
        andalso (R < id({a, tuple}))
        andalso (R < id([]))
        andalso (R < id(<<"a binary">>)).

%% --- order consistency: identity terms carry a genuine TOTAL order -----------
%% For two fresh refs exactly one of A<B / B<A holds (trichotomy + antisymmetry),
%% < is irreflexive, and < is transitive through a pid. == and < are mutually
%% exclusive. This is the representation-INDEPENDENT law both VMs must satisfy
%% (no concrete ordering direction is asserted — only its consistency).
c_order_consistency(_) ->
    A = make_ref(),
    B = make_ref(),
    P = self(),
    Lt = A < B,
    Gt = B < A,
    %% trichotomy for distinct refs: exactly one strict direction
    (Lt =/= Gt)
        andalso (Lt orelse Gt)
        %% irreflexivity
        andalso (not (A < A))
        andalso (not (P < P))
        %% antisymmetry consistent with =< / >=
        andalso ((A =< B) =:= not (B < A))
        andalso ((A >= B) =:= not (A < B))
        %% equality excludes strict inequality
        andalso (not ((A =:= B) andalso Lt))
        %% transitivity via a pid: refs order below the pid, pid below a tuple
        andalso (A < P) andalso (P < id({z})) andalso (A < id({z})).

%% --- node/0 and node/1 on local containers: all nonode@nohost ---------------
%% This node is non-distributed, so node() is the atom nonode@nohost, and the
%% owning node of a locally-created pid or ref is exactly node().
c_node_local(_) ->
    P = self(),
    R = make_ref(),
    (node() =:= nonode@nohost)
        andalso (node(P) =:= nonode@nohost)
        andalso (node(R) =:= nonode@nohost)
        andalso (node(P) =:= node())
        andalso (node(R) =:= node())
        andalso is_atom(node(P)).

%% --- pid/ref inside tuples: construction, matching, element ops preserve id --
%% A tuple carrying a pid and a ref round-trips through pattern match, element/2,
%% tuple_to_list, and setelement/3 with the identities intact.
c_pid_in_tuple(_) ->
    P = self(),
    R = make_ref(),
    T = {P, R, other},
    {P1, R1, other} = T,
    (P1 =:= P) andalso (R1 =:= R)
        andalso (element(1, T) =:= P)
        andalso (element(2, T) =:= R)
        andalso (tuple_to_list(T) =:= [P, R, other])
        andalso (setelement(3, T, P) =:= {P, R, P})
        andalso (list_to_tuple([P, R]) =:= {P, R}).

%% --- pid/ref inside maps, as VALUES and as KEYS ------------------------------
%% Refs and pids serve as map values and as map keys; maps:get retrieves them by
%% identity; two maps built with the SAME ref key are equal, with DISTINCT ref
%% keys are unequal.
c_ref_in_map(_) ->
    P = self(),
    R = make_ref(),
    Mv = #{pid => P, ref => R},
    Mk = #{R => tagged, P => owner},
    A = make_ref(),
    B = make_ref(),
    (maps:get(pid, Mv) =:= P)
        andalso (maps:get(ref, Mv) =:= R)
        andalso (maps:get(R, Mk) =:= tagged)
        andalso (maps:get(P, Mk) =:= owner)
        andalso (#{R => 1} =:= #{R => 1})
        andalso (#{A => 1} =/= #{B => 1})
        andalso (#{k => P} =:= #{k => P}).

%% --- pid/ref inside lists: membership, length, head/tail, equality ----------
%% A list of identity terms preserves them positionally; a locally-defined
%% membership check (no lists:*) finds a ref by identity; two lists built from
%% the same terms are equal.
c_containers_in_list(_) ->
    P = self(),
    R = make_ref(),
    L = [P, R, P],
    [H | T] = L,
    (H =:= P)
        andalso (T =:= [R, P])
        andalso (len(L, 0) =:= 3)
        andalso member(R, L)
        andalso (not member(make_ref(), L))
        andalso ([P, R] =:= [P, R]).

%% --- nested containers + term_to_binary round-trip preserve identity ---------
%% A pid and a ref buried inside a tuple-of-map-of-list survive deconstruction
%% with identity intact, and term_to_binary/binary_to_term is a within-VM
%% round-trip identity for both a bare pid and a bare ref (this is a per-VM
%% property — no cross-VM byte value is compared).
c_nested_round_trip(_) ->
    P = self(),
    R = make_ref(),
    Nested = {tag, #{p => P, rs => [R, R]}, [P]},
    {tag, Inner, [P2]} = Nested,
    [R2, R3] = maps:get(rs, Inner),
    (P2 =:= P) andalso (R2 =:= R) andalso (R3 =:= R)
        andalso (maps:get(p, Inner) =:= P)
        andalso (binary_to_term(term_to_binary(P)) =:= P)
        andalso (binary_to_term(term_to_binary(R)) =:= R)
        andalso (binary_to_term(term_to_binary(Nested)) =:= Nested).

%% --- send/receive preserving pid & ref identity ------------------------------
%% A spawned child replies {ChildPid, Ref, payload}; the received sender pid is a
%% pid, is distinct from self(), and the reply is selected by the make_ref()
%% created immediately before the receive (the recv-marker shape). Mailbox is
%% verified empty before returning.
c_send_recv_identity(_) ->
    Me = self(),
    Ref = make_ref(),
    Child = spawn(zigvm_node_container_SUITE, child, [Me, Ref]),
    Got = receive
              {From, Ref, payload} ->
                  is_pid(From)
                      andalso (From =:= Child)
                      andalso (From =/= Me)
                      andalso is_pid(Child)
              after 1000 -> false
          end,
    Got andalso mbox_empty().

%% --- spawned entry point (terminates by construction) ------------------------
child(Parent, Ref) -> Parent ! {self(), Ref, payload}.

%% --- local helpers (self-contained; no lists:* to load) ----------------------
mbox_empty() -> receive _ -> false after 0 -> true end.

len([], Acc) -> Acc;
len([_ | T], Acc) -> len(T, Acc + 1).

member(_X, []) -> false;
member(X, [X | _]) -> true;
member(X, [_ | T]) -> member(X, T).
