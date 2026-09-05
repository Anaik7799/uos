%% gap-fun-info (DIVERGENCE 652): erlang:fun_info/2's DETERMINISTIC items run
%% byte-EQ vs OTP-30 (was undef — `.justified`, unreachable). External `fun M:F/A`
%% funs are FULLY byte-EQ (type=external, module, name, arity, env=[]); local
%% closures are byte-EQ for arity/type/env. A local closure's module/name (+ every
%% fun's uniq/index/pid) need compile metadata this fun term does not carry — the
%% honest `deferred-funmeta` residual (clean badarg), so the row stays `.justified`.
%%   zigvm run zigvm_fun_info.beam t --code-path <stdlib+kernel ebin>
%%   erl -pa ... -eval 'io:format("~p~n",[zigvm_fun_info:t()]), init:stop().'
-module(zigvm_fun_info).
-export([t/0, helper/1]).
helper(X) -> X.
t() ->
    Ext = fun zigvm_fun_info:helper/1,
    Loc = fun(X) -> X + 1 end,
    {erlang:fun_info(Ext, type),   erlang:fun_info(Ext, module), erlang:fun_info(Ext, name),
     erlang:fun_info(Ext, arity),  erlang:fun_info(Ext, env),
     erlang:fun_info(Loc, type),   erlang:fun_info(Loc, arity),  erlang:fun_info(Loc, env)}.
