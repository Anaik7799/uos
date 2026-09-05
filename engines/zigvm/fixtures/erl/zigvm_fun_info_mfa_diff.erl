%% zigvm_fun_info_mfa_diff — compiled differential for fun introspection
%% (DIVERGENCE 727 + 741). A LOCAL closure's module + compiler-generated name +
%% arity (727) and its FunT index + uniq (741, the OldIndex/OldUniq via fun_meta)
%% now come from the make_fun3-populated Machine.fun_meta, so fun_info_mfa/1 and
%% fun_info(F, module|name|index|uniq) are byte-EQ (were undef/badarg —
%% deferred_funmeta). new_uniq/new_index (md5-based) stay a disclosed residual.
%%
%% Run on BOTH VMs (no code-path needed; erlang: BIFs):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_fun_info_mfa_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_fun_info_mfa_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_fun_info_mfa_diff.beam t 0
%% Byte-EQ verdict (both):
%%   {mfa,{zigvm_fun_info_mfa_diff,'-t/1-fun-0-',1},mod,{module,zigvm_fun_info_mfa_diff},
%%    name,{name,'-t/1-fun-0-'},arity,{arity,1},type,{type,local},index,{index,0},uniq,{uniq,<u>}}
-module(zigvm_fun_info_mfa_diff).
-export([t/1]).
t(_) ->
    F = fun(X) -> X + 1 end,
    Mfa  = erlang:fun_info_mfa(F),
    Mod  = erlang:fun_info(F, module),
    Name = erlang:fun_info(F, name),
    Ar   = erlang:fun_info(F, arity),
    Ty   = erlang:fun_info(F, type),
    Ix   = erlang:fun_info(F, index),   %% DIVERGENCE 741
    Uq   = erlang:fun_info(F, uniq),    %% DIVERGENCE 741
    erlang:display({mfa, Mfa, mod, Mod, name, Name, arity, Ar, type, Ty, index, Ix, uniq, Uq}).
