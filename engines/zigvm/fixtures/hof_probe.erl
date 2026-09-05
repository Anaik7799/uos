%% hof_probe — a minimal entry module exercising the preloaded stock stdlib:
%% higher-order lists/maps + string/proplists + the collection modules + digraph
%% + re.erl wrappers + calendar + timer + base64 + uri_string + rand + math + erl_scan/erl_parse + gap-hof-batch (14 pure stdlib modules: binary/sofs/graph/erl_internal/…),
%% all preloaded by the `run` CLI. In-process LAW gap-hof-stdlib. Pinned OTP-30
%% erlc; byte-mirrored src/hof_probe.beam.
-module(hof_probe).
-export([go/0]).

go() ->
    M  = lists:map(fun(X) -> X * X end, [1, 2, 3]),
    F  = lists:foldl(fun(X, A) -> X + A end, 0, [1, 2, 3, 4]),
    Fl = lists:filter(fun(X) -> X rem 2 =:= 0 end, [1, 2, 3, 4]),
    Al = lists:all(fun(X) -> X > 0 end, [1, 2, 3]),
    R  = lists:reverse([1, 2, 3]),
    Mm = maps:map(fun(_K, V) -> V + 1 end, #{a => 1}),
    Mf = maps:fold(fun(_K, V, Acc) -> V + Acc end, 0, #{a => 1, b => 2}),
    S  = string:uppercase(<<"ab">>),
    P  = proplists:get_value(k, [{k, 7}]),
    St = sets:size(sets:from_list([3, 1, 2, 1])),
    Gt = gb_trees:get(2, gb_trees:from_orddict([{1, a}, {2, b}])),
    Os = ordsets:to_list(ordsets:add_element(2, ordsets:from_list([3, 1]))),
    Qq = queue:to_list(queue:in(3, queue:from_list([1, 2]))),
    Dd = dict:fetch(b, dict:from_list([{a, 1}, {b, 2}])),
    Od = orddict:to_list(orddict:store(c, 3, orddict:from_list([{a, 1}, {b, 2}]))),
    Ar = array:get(1, array:from_list([10, 20, 30])),
    Re = re:replace("a-b", "-", "_", [{return, binary}]),
    Gs = gb_sets:to_list(gb_sets:add_element(2, gb_sets:from_list([3, 1]))),
    Dg = begin
             G = digraph:new(),
             digraph:add_vertex(G, a),
             digraph:add_vertex(G, b),
             digraph:add_edge(G, a, b),
             digraph:get_path(G, a, b)
         end,
    Cal = calendar:day_of_the_week(2026, 7, 30),
    Tmr = timer:hms(1, 2, 3),
    B64 = base64:encode(<<"hi">>),
    Uri = uri_string:quote("a b"),
    Rnd = element(1, rand:uniform_s(1000, rand:seed_s(exsss, {42, 42, 42}))),
    Mth = trunc(math:sqrt(144.0)),
    Ann = erl_anno:line(erl_anno:set_line(7, erl_anno:new(1))),
    {ok, PToks, _} = erl_scan:string("{tag, <<\"hi\">>, [1, 2]}."),
    {ok, [PForm]} = erl_parse:parse_exprs(PToks),
    Prs = erl_parse:normalise(PForm),
    Bat = {binary:encode_hex(<<255, 0, 16>>), erl_internal:bif(is_integer, 1),
           otp_internal:obsolete(lists, map, 2),
           graph:no_vertices(graph:add_vertex(graph:new(), a)),
           io_lib_fread:fread("~d", "42"),
           lists:sort(sofs:to_external(sofs:union(sofs:set([1, 2]), sofs:set([2, 3])))),
           is_map(erl_stdlib_errors:format_error(badarg, [{lists, seq, [5, 1, 0], []}, badarg])),
           element(1, random:uniform_s(100, {5, 5, 5})),
           element(1, hd(erl_id_trans:parse_transform([{attribute, 1, module, m}], []))),
           is_map(edlin_key:get_key_map()), edlin_type_suggestion:get_arity(lists, seq, []),
           is_list(erl_expand_records:module([{attribute, 1, module, m}, {attribute, 1, record, {r, [{record_field, 1, {atom, 1, a}}]}}], []))},
    {M, F, Fl, Al, R, Mm, Mf, S, P, St, Gt, Os, Qq, Dd, Od, Ar, Re, Gs, Dg, Cal, Tmr, B64, Uri, Rnd, Mth, Ann, Prs, Bat}.
