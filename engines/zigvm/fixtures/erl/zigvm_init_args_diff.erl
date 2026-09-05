%% zigvm_init_args_diff — gap-erl-cli-args (DIVERGENCE 598).
%% The RUNTIME-CAPABILITY-EQUIVALENCE differential for init:get_plain_arguments/0
%% + init:get_argument/1 — the drop-in-erl CLI-argument contract escripts/release
%% scripts read. Byte-IDENTICAL on zigvm and pinned OTP-30. Kept SMALL (2 BIF calls,
%% few flags) so the erl boot stays fast in-sandbox and deterministic — the
%% COMPREHENSIVE contract (multi-occurrence, boot-consumed, missing) is proven by
%% the in-process LAW gap-erl-cli-args (proc.zig), which needs no boot path.
%% Invoke:  … -myflag a -s zigvm_init_args_diff t -extra e1 e2
-module(zigvm_init_args_diff).
-export([t/0]).
t() ->
    erlang:display({plain,  init:get_plain_arguments()}), % -extra tokens as strings -> ["e1","e2"]
    erlang:display({myflag, init:get_argument(myflag)}),  % user flag                -> {ok,[["a"]]}
    init:stop().
