%% zigvm_procinfo_keys_diff — compiled differential for process_info/2 live-state
%% items (DIVERGENCE 735). `erlang:process_info(self(), Item)` for Item ∈
%% {current_function, catchlevel, reductions, stack_size} raised `badarg` on zigvm
%% (the item wasn't in the accepted subset) where OTP returns a value. A valid item
%% must RETURN, not badarg (FM-OBS-1).
%%
%% VALUE differential: `current_function` is BYTE-EQ (the deterministic mfa of the
%% function that called process_info). `catchlevel`/`reductions`/`stack_size` are
%% EQUIV (real functions of the process's live state — the absolute values are
%% impl/driver-specific) so this asserts they RETURN an integer, not their exact
%% value.
%%
%% Run on BOTH VMs (no stdlib needed):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_procinfo_keys_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_procinfo_keys_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_procinfo_keys_diff.beam t 0
%% Byte-EQ verdict (both): {procinfo_keys,cf,{zigvm_procinfo_keys_diff,check,0},
%%   cl_int,true,red_int,true,ss_int,true}
-module(zigvm_procinfo_keys_diff).
-export([t/1, check/0]).
t(_) ->
    erlang:display(check()).
check() ->
    {current_function, CF} = erlang:process_info(self(), current_function),
    {catchlevel, Cl} = erlang:process_info(self(), catchlevel),
    {reductions, Rd} = erlang:process_info(self(), reductions),
    {stack_size, Ss} = erlang:process_info(self(), stack_size),
    {procinfo_keys, cf, CF,
     cl_int, is_integer(Cl), red_int, is_integer(Rd), ss_int, is_integer(Ss)}.
