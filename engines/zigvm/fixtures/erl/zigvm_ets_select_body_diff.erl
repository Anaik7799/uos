%% Durable end-to-end differential for the match-spec BODY → eval wiring
%% (DIVERGENCE 632). ets:select with COMPUTED bodies must be byte-EQ on zigvm
%% and pinned OTP-30. Run: `zigvm run zigvm_ets_select_body_diff.beam t 0`
%% and `erl -pa DIR -eval 'zigvm_ets_select_body_diff:t(0),init:stop().'`.
%% Expected (both): {sum,[13,25]} {swap,[{3,10},{5,20}]} {elem,[10,20]}
%%                  {const,[{a,b},{a,b}]}
-module(zigvm_ets_select_body_diff).
-export([t/1]).
t(_) ->
    T = ets:new(t, [ordered_set]),
    ets:insert(T, {10,3}),
    ets:insert(T, {20,5}),
    erlang:display({sum,   ets:select(T, [{{'$1','$2'}, [], [{'+','$1','$2'}]}])}),
    erlang:display({swap,  ets:select(T, [{{'$1','$2'}, [], [{{'$2','$1'}}]}])}),
    erlang:display({elem,  ets:select(T, [{{'$1','$2'}, [], [{element,1,{{'$1','$2'}}}]}])}),
    erlang:display({const, ets:select(T, [{{'$1','$2'}, [], [{const,{a,b}}]}])}),
    ok.
