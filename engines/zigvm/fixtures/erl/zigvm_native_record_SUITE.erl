%% zigvm_native_record_SUITE — a PURE, VM-executable subset of record behaviour
%% in the common_test SUITE shape (`all/0` + `Case(Config)` funs) with NO
%% common_test / test_server dependency (CT-on-zigvm is Epoch E7). It targets
%% zigvm's native-record support (E3.14): construction with defaults, field
%% access, functional field update, pattern extraction, record guards
%% (is_record/2,3 and `#rec{}` patterns in case/function heads), record_info,
%% the record↔tuple identity that lets element/2 & setelement/3 stand in for
%% field ops, the compile-time field-index expression `#rec.field`, nested
%% records, record term ordering (tuple order), records in a comprehension, and
%% expression-valued field defaults.
%%
%% SCOPE / EXCLUSIONS (honesty): the OTP-30 native reflection module `records:`
%% (`records:create/4`, `get_name/1`, `get/2`, `update/4`, `get_definition/2`,
%% …) is DELIBERATELY EXCLUDED — zigvm implements it (E3.14, bifs/records.zig)
%% but the pinned oracle toolchain available for verification is OTP-28-class,
%% where the whole `records` module is absent (`records:get_name(x)` raises
%% `error:undef`). A byte-EQ curated case must run true on BOTH VMs, so those
%% BIFs have no oracle to compare against and are left to the pinned-OTP-30
%% oracle build (the check_process_code/get_definition precedent). Everything
%% here is classic record sugar that erlc expands to tuple ops, so it runs
%% identically on every BEAM and on zigvm. No error-path (badrecord/badarg
%% catch) cases — try/catch reason shapes are excluded per the curation charter.
%%
%% Discipline: each case returns the atom `true` on success; every runtime
%% operand (field VALUES) is routed through the exported ?MODULE:id/1 so
%% constant folding cannot bypass the VM (record_info/1,2 and `#rec.field` are
%% inherently compile-time and expand to identical literals on both VMs). No
%% processes, no receive, no timers — pure term computation.
-module(zigvm_native_record_SUITE).

-export([all/0,
         c_construct_default/1, c_field_access/1, c_field_update/1,
         c_pattern_match/1, c_is_record_guard/1, c_record_info/1,
         c_record_as_tuple/1, c_field_index/1, c_nested_record/1,
         c_head_dispatch/1, c_record_ordering/1, c_list_of_records/1,
         c_default_exprs/1,
         %% id/1 is the constant-folding firewall (exported ?MODULE call).
         id/1]).

-record(point,  {x = 0, y = 0}).
-record(circle, {center = #point{}, r = 1}).
-record(dflt,   {a = 1 + 2, b = [x, y, z], c = {t, u}}).
-record(rec9,   {f1, f2, f3, f4, f5, f6, f7, f8, f9}).

%% The suite manifest (common_test `all/0` contract). MIRRORED in order by
%% harness/suite_runner.ml's native_record spec case_names (ncases/1 lockstep).
all() ->
    [c_construct_default, c_field_access, c_field_update,
     c_pattern_match, c_is_record_guard, c_record_info,
     c_record_as_tuple, c_field_index, c_nested_record,
     c_head_dispatch, c_record_ordering, c_list_of_records,
     c_default_exprs].

%% Identity through an exported call — the compiler cannot constant-fold across
%% it, so seed values genuinely travel through the VM.
id(X) -> X.

%% --- construction: explicit fields + the record's declared defaults ---------
c_construct_default(_) ->
    P0 = #point{},
    P1 = #point{x = id(1), y = id(2)},
    P2 = #point{y = id(7)},
    (P0#point.x =:= 0) andalso (P0#point.y =:= 0)
        andalso (P1#point.x =:= 1) andalso (P1#point.y =:= 2)
        andalso (P2#point.x =:= 0) andalso (P2#point.y =:= 7).

%% --- field access on a built record -----------------------------------------
c_field_access(_) ->
    P = #point{x = id(10), y = id(20)},
    C = #circle{center = P, r = id(3)},
    (P#point.x =:= 10) andalso (P#point.y =:= 20)
        andalso (C#circle.r =:= 3)
        andalso (C#circle.center =:= P).

%% --- functional update: named-field update, source record unchanged ---------
c_field_update(_) ->
    P = #point{x = id(1), y = id(2)},
    Px = P#point{x = id(9)},
    Pxy = P#point{x = id(5), y = id(6)},
    (Px#point.x =:= 9) andalso (Px#point.y =:= 2)
        andalso (Pxy#point.x =:= 5) andalso (Pxy#point.y =:= 6)
        andalso (P#point.x =:= 1) andalso (P#point.y =:= 2).

%% --- pattern extraction: `#rec{field=Var}` binds field values ---------------
c_pattern_match(_) ->
    P = #point{x = id(3), y = id(4)},
    #point{x = X, y = Y} = P,
    #point{x = X2} = P,
    (X =:= 3) andalso (Y =:= 4) andalso (X2 =:= 3).

%% --- record guards: is_record/2, is_record/3, and `#rec{}` case patterns ----
c_is_record_guard(_) ->
    %% scrutinees pass through id/1 so the record match/guard is a genuine
    %% RUNTIME tuple test, not a compile-time-resolved literal.
    P = id(#point{x = id(1)}),
    C = id(#circle{r = id(2)}),
    NotR = id({point, 1}),                 %% wrong arity: not a #point{}
    G1 = is_record(P, point),
    G2 = is_record(P, point, 3),
    G3 = (not is_record(P, circle)),
    G4 = (not is_record(NotR, point)),
    G5 = case C of #circle{} -> true; _ -> false end,
    G6 = case P of #circle{} -> false; #point{} -> true; _ -> false end,
    G1 andalso G2 andalso G3 andalso G4 andalso G5 andalso G6.

%% --- record_info/2: declared size (arity incl. tag) and field-name order ----
c_record_info(_) ->
    (record_info(size, point) =:= 3)
        andalso (record_info(fields, point) =:= [x, y])
        andalso (record_info(size, circle) =:= 3)
        andalso (record_info(fields, circle) =:= [center, r])
        andalso (record_info(size, rec9) =:= 10).

%% --- record ↔ tuple identity: element/2 & setelement/3 mirror record ops ----
c_record_as_tuple(_) ->
    P = #point{x = id(1), y = id(2)},
    (P =:= {point, 1, 2})
        andalso (element(1, P) =:= point)
        andalso (element(#point.x, P) =:= 1)
        andalso (element(#point.y, P) =:= 2)
        andalso (setelement(#point.x, P, id(7)) =:= #point{x = 7, y = 2})
        andalso (tuple_to_list(P) =:= [point, 1, 2]).

%% --- `#rec.field`: the compile-time 1-based field index into the tuple ------
c_field_index(_) ->
    (#point.x =:= 2) andalso (#point.y =:= 3)
        andalso (#circle.center =:= 2) andalso (#circle.r =:= 3)
        andalso (#rec9.f1 =:= 2) andalso (#rec9.f9 =:= 10).

%% --- nested records: construct, access-through, and functional deep update --
c_nested_record(_) ->
    C = #circle{center = #point{x = id(1), y = id(2)}, r = id(3)},
    Ctr = C#circle.center,
    C2 = C#circle{center = Ctr#point{x = id(99)}},
    ((C#circle.center)#point.x =:= 1)
        andalso ((C2#circle.center)#point.x =:= 99)
        andalso ((C2#circle.center)#point.y =:= 2)
        andalso (C2#circle.r =:= 3)
        andalso ((C#circle.center)#point.x =:= 1).   %% original untouched

%% --- record patterns dispatch function heads + guards -----------------------
c_head_dispatch(_) ->
    P = #point{x = id(3), y = id(4)},
    C = #circle{center = #point{}, r = id(5)},
    (sum_or_area(P) =:= 7)                 %% #point head: x + y
        andalso (sum_or_area(C) =:= 25)    %% #circle head: r*r
        andalso (classify(P) =:= point)
        andalso (classify(C) =:= circle)
        andalso (classify(id({a, b, c})) =:= other).

%% --- record term ordering IS tuple ordering (arity, then element-wise) ------
c_record_ordering(_) ->
    P1 = #point{x = id(1), y = id(2)},
    P2 = #point{x = id(1), y = id(3)},
    P3 = #point{x = id(2), y = id(0)},
    (P1 < P2) andalso (P2 < P3) andalso (P1 < P3)
        andalso (P1 =< P1) andalso (P3 > P1)
        andalso (P1 =/= P2) andalso (P1 =:= #point{x = 1, y = 2}).

%% --- a list comprehension that constructs and destructures records ----------
c_list_of_records(_) ->
    Ps = [#point{x = id(1), y = id(10)},
          #point{x = id(2), y = id(20)},
          #point{x = id(3), y = id(30)}],
    Xs = [X || #point{x = X} <- Ps],
    Sums = [A + B || #point{x = A, y = B} <- Ps],
    (Xs =:= [1, 2, 3]) andalso (Sums =:= [11, 22, 33]).

%% --- expression-valued field defaults evaluate at construction --------------
c_default_exprs(_) ->
    D = #dflt{},
    R9 = #rec9{f1 = id(a), f9 = id(z)},
    (D#dflt.a =:= 3) andalso (D#dflt.b =:= [x, y, z]) andalso (D#dflt.c =:= {t, u})
        andalso (R9#rec9.f1 =:= a) andalso (R9#rec9.f9 =:= z)
        andalso (R9#rec9.f5 =:= undefined).   %% unset field defaults to undefined

%% --- local helpers: record-pattern function heads (not exported) ------------
sum_or_area(#point{x = X, y = Y}) -> X + Y;
sum_or_area(#circle{r = R}) -> R * R.

classify(R) when is_record(R, point)  -> point;
classify(R) when is_record(R, circle) -> circle;
classify(_) -> other.
