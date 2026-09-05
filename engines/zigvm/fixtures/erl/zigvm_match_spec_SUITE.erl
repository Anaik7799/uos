%% Curated PURE subset of erts/emulator/test/match_spec_SUITE.erl (E7 suite
%% closure). The real suite exercises erlang:match_spec_test/3 plus live
%% tracing (trace_pattern/seq_trace/silent), maps-in-specs, guard arithmetic
%% and andalso/orelse — driven by CT peers, rpc and trace delivery. These
%% cases MIRROR its table-type match_spec_test/3 core (test_ms's primitive:
%% head patterns, guard conjunctions, value/predicate bodies, first-clause
%% wins, boxed-vs-small literal heads, malformed-spec rejection) as
%% self-contained BOOLEAN assertions, restricted to the guard/body grammar
%% zigvm's S23 compiler supports EQ (DIVERGENCE_LOG entry 13(b) bounded
%% subset): guards {is_integer|is_atom|is_list,'$V'} and {'>'|'<'|'=:=','$V',
%% Literal}; bodies ['$_'] | ['$N'] | [{{'$a','$b',...}}] | [true]. Guard
%% CONJUNCTION (the guard list) expresses the suite's andalso intent — the
%% andalso/orelse/arithmetic FORMS themselves are outside the bounded subset
%% and are excluded, as are maps-in-specs, trace-type specs and {const,_}.
%% The 4-tuple {ok,Result,[],[]} success shape is asserted in full (both VMs
%% return flags [] / warnings [] for table type); malformed specs assert only
%% element(1,_) =:= error (the error TEXT differs by design). Every subject
%% and every spec is routed through the EXPORTED ?MODULE:id/1 so the runtime
%% match-spec compiler + engine are exercised, never erlc's folder. No ct/
%% port/node/trace/io dependency — runnable directly on the zigvm CLI byte-EQ
%% vs OTP-30.
-module(zigvm_match_spec_SUITE).
-export([all/0, id/1, c_whole_object/1, c_head_vars_swap/1, c_head_literals/1,
         c_type_guards/1, c_compare_guards/1, c_eq_exact_guard/1,
         c_guard_conjunction/1, c_multi_clause/1, c_body_variable/1,
         c_predicate_true/1, c_nested_head/1, c_bad_spec/1]).

all() ->
    [c_whole_object, c_head_vars_swap, c_head_literals, c_type_guards,
     c_compare_guards, c_eq_exact_guard, c_guard_conjunction, c_multi_clause,
     c_body_variable, c_predicate_true, c_nested_head, c_bad_spec].

%% External-call identity: operands routed through here reach the VM as
%% runtime values, never as compile-time constants (erlc cannot fold across
%% an exported call — the zigvm_big_SUITE c_bitwise_2pow pattern).
id(X) -> X.

%% The one observation under test: the table-type tester (ets:test_ms's
%% primitive). Object and spec both arrive as runtime values.
mst(Obj, Ms) ->
    erlang:match_spec_test(?MODULE:id(Obj), ?MODULE:id(Ms), table).

%% '$_' returns the WHOLE object; a fully-literal head matches by exact
%% equality; a mismatching literal head yields Result = false. The full
%% {ok,Result,[],[]} 4-tuple is pinned (flags/warnings are [] for table).
c_whole_object(_) ->
    Obj = {a,1,[x]},
    (mst(Obj, [{'_',[],['$_']}]) =:= {ok,{a,1,[x]},[],[]})
        andalso (mst(Obj, [{{a,1,[x]},[],['$_']}]) =:= {ok,{a,1,[x]},[],[]})
        andalso (mst(Obj, [{{b,1,[x]},[],['$_']}]) =:= {ok,false,[],[]}).

%% Head variables bind positionally; the {{'$a','$b'}} body CONSTRUCTS a
%% tuple from bindings (the classic swap spec); an arity mismatch is a clean
%% no-match.
c_head_vars_swap(_) ->
    Ms = [{{'$1','$2'},[],[{{'$2','$1'}}]}],
    (mst({10,20}, Ms) =:= {ok,{20,10},[],[]})
        andalso (mst({banan,[1,2]}, Ms) =:= {ok,{[1,2],banan},[],[]})
        andalso (mst({1,2,3}, Ms) =:= {ok,false,[],[]}).

%% do_boxed_and_small lifted: boxed literal heads (float / bignum / binary /
%% fresh ref) against the small-headed subject {0,3} must yield false — the
%% boxed-vs-immediate comparison must not confuse the engine. The matching
%% direction: a small literal + variable head extracts the second element.
c_head_literals(_) ->
    Obj = {0,3},
    (mst(Obj, [{{1.47,'_'},[],['$_']}]) =:= {ok,false,[],[]})
        andalso (mst(Obj, [{{12345678901234567890,'_'},[],['$_']}])
                 =:= {ok,false,[],[]})
        andalso (mst(Obj, [{{<<1,2,3,4>>,'_'},[],['$_']}]) =:= {ok,false,[],[]})
        andalso (mst(Obj, [{{make_ref(),'_'},[],['$_']}]) =:= {ok,false,[],[]})
        andalso (mst(Obj, [{{0,'$1'},[],['$1']}]) =:= {ok,3,[],[]}).

%% Type-test guards: is_integer (integers incl. bignums, NOT floats),
%% is_atom, is_list (nil and cons, NOT binaries).
c_type_guards(_) ->
    MsI = [{'$1',[{is_integer,'$1'}],['$_']}],
    MsA = [{'$1',[{is_atom,'$1'}],['$_']}],
    MsL = [{'$1',[{is_list,'$1'}],['$_']}],
    Big = ?MODULE:id(1 bsl 64),
    (mst(5, MsI) =:= {ok,5,[],[]})
        andalso (mst(Big, MsI) =:= {ok,Big,[],[]})
        andalso (mst(5.0, MsI) =:= {ok,false,[],[]})
        andalso (mst(hej, MsI) =:= {ok,false,[],[]})
        andalso (mst(hej, MsA) =:= {ok,hej,[],[]})
        andalso (mst({1}, MsA) =:= {ok,false,[],[]})
        andalso (mst([1,2], MsL) =:= {ok,[1,2],[],[]})
        andalso (mst([], MsL) =:= {ok,[],[],[]})
        andalso (mst(<<1>>, MsL) =:= {ok,false,[],[]}).

%% '>' / '<' guards are the ARITHMETIC-then-term total order: mixed
%% int/float comparison is by value, bignums compare exactly, and any atom
%% orders above every number.
c_compare_guards(_) ->
    Gt4 = [{'$1',[{'>','$1',4}],['$_']}],
    Lt0 = [{'$1',[{'<','$1',0}],['$_']}],
    GtF = [{'$1',[{'>','$1',4.5}],['$_']}],
    GtBig = [{'$1',[{'>','$1',1 bsl 64}],['$_']}],
    BigUp = ?MODULE:id((1 bsl 64) + 1),
    (mst(5, Gt4) =:= {ok,5,[],[]})
        andalso (mst(4, Gt4) =:= {ok,false,[],[]})
        andalso (mst(-1, Lt0) =:= {ok,-1,[],[]})
        andalso (mst(0, Lt0) =:= {ok,false,[],[]})
        andalso (mst(5, GtF) =:= {ok,5,[],[]})
        andalso (mst(4, GtF) =:= {ok,false,[],[]})
        andalso (mst(BigUp, GtBig) =:= {ok,BigUp,[],[]})
        andalso (mst(1 bsl 64, GtBig) =:= {ok,false,[],[]})
        andalso (mst(atom_wins, [{'$1',[{'>','$1',1000000}],['$_']}])
                 =:= {ok,atom_wins,[],[]}).

%% '=:=' guard is EXACT equality: 5.0 =:= 5 is false (no arithmetic
%% coercion), atoms and list literals compare structurally.
c_eq_exact_guard(_) ->
    Eq5 = [{'$1',[{'=:=','$1',5}],['$_']}],
    (mst(5, Eq5) =:= {ok,5,[],[]})
        andalso (mst(5.0, Eq5) =:= {ok,false,[],[]})
        andalso (mst(blurf, [{'$1',[{'=:=','$1',blurf}],['$_']}])
                 =:= {ok,blurf,[],[]})
        andalso (mst([1,2,3], [{'$1',[{'=:=','$1',[1,2,3]}],['$_']}])
                 =:= {ok,[1,2,3],[],[]})
        andalso (mst([1,2], [{'$1',[{'=:=','$1',[1,2,3]}],['$_']}])
                 =:= {ok,false,[],[]}).

%% A guard LIST is a conjunction (the suite's andalso intent, in-subset):
%% every guard must hold, left to right — one failing type test or bound
%% check rejects the whole clause.
c_guard_conjunction(_) ->
    Ms = [{'$1',[{is_integer,'$1'},{'>','$1',3},{'<','$1',10}],['$_']}],
    (mst(5, Ms) =:= {ok,5,[],[]})
        andalso (mst(2, Ms) =:= {ok,false,[],[]})
        andalso (mst(12, Ms) =:= {ok,false,[],[]})
        andalso (mst(hej, Ms) =:= {ok,false,[],[]}).

%% Multi-clause specs: the FIRST matching clause produces the result
%% (erl_db_util clause order); no clause matching yields false.
c_multi_clause(_) ->
    Ms = [{{a,'$1'},[],['$1']},
          {{'$1','$2'},[],[{{'$1','$2'}}]},
          {'$1',[{is_atom,'$1'}],['$_']}],
    (mst({a,42}, Ms) =:= {ok,42,[],[]})
        andalso (mst({b,7}, Ms) =:= {ok,{b,7},[],[]})
        andalso (mst(zed, Ms) =:= {ok,zed,[],[]})
        andalso (mst([1], Ms) =:= {ok,false,[],[]}).

%% A ['$N'] body projects ONE binding out of a wider head.
c_body_variable(_) ->
    (mst({x,y,z}, [{{'$1','$2','$3'},[],['$2']}]) =:= {ok,y,[],[]})
        andalso (mst({x,y,z}, [{{'$1','$2','$3'},[],['$3']}]) =:= {ok,z,[],[]})
        andalso (mst({x,y}, [{{'$1','$2','$3'},[],['$2']}]) =:= {ok,false,[],[]}).

%% The [true] predicate body (select_count/select_delete's form): a match
%% yields the atom true, a non-match yields false.
c_predicate_true(_) ->
    MsI = [{'$1',[{is_integer,'$1'}],[true]}],
    MsT = [{{'$1','_'},[],[true]}],
    (mst(7, MsI) =:= {ok,true,[],[]})
        andalso (mst(hej, MsI) =:= {ok,false,[],[]})
        andalso (mst({x,y}, MsT) =:= {ok,true,[],[]})
        andalso (mst(nope, MsT) =:= {ok,false,[],[]}).

%% Head patterns nest: variables and literals inside tuples inside lists
%% inside tuples all bind/compare at depth.
c_nested_head(_) ->
    Ms = [{{a,{'$1',[b,'$2']},'$3'},[],[{{'$1','$2','$3'}}]}],
    (mst({a,{1,[b,2]},c}, Ms) =:= {ok,{1,2,c},[],[]})
        andalso (mst({a,{1,[x,2]},c}, Ms) =:= {ok,false,[],[]})
        andalso (mst({a,{1,[b,2,3]},c}, Ms) =:= {ok,false,[],[]}).

%% Malformed specs are a clean {error,Errors} RESULT, never an exception:
%% a clause that is not a 3-tuple, and a clause that is not a tuple at all.
%% Only the error TAG is asserted — the diagnostic text differs by design.
c_bad_spec(_) ->
    (element(1, mst({1,2}, [{'_'}])) =:= error)
        andalso (element(1, mst({1,2}, [not_a_clause])) =:= error)
        andalso (element(1, mst({1,2}, [{'_',[],['$_'],extra}])) =:= error).
