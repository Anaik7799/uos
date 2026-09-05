%% zigvm_localtime_diff — compiled differential for the LOCAL-time calendar family
%% (DIVERGENCE 731). `erlang:universaltime_to_localtime/1`, `localtime/0`, `date/0`,
%% `time/0` were `.justified` (deferred → undef): `calendar:local_time/0` and
%% `sys:statistics(_,get)` (which calls `erlang:localtime/0`) crashed `{undef,...}`.
%% Now wired to the pure Gregorian pair + the host TZ offset (`prim_file.tzOffsetAt`,
%% reads `/etc/localtime`).
%%
%% VALUE differential: `universaltime_to_localtime/1` is DETERMINISTIC given the host
%% zone, so BOTH VMs (same host `/etc/localtime`) return byte-EQ tuples — tested on a
%% SUMMER (DST) and a WINTER (standard) UTC instant so the zone's DST rule is exercised
%% both ways. `localtime/0`/`date/0`/`time/0` are time-varying → SHAPE + decomposition
%% (date == element(1,localtime), time == element(2,localtime)).
%%
%% HONEST SCOPE: `erlang:localtime_to_universaltime/1,2` stay deferred (the /2 `IsDst`
%% flag needs the zone's separate std+DST offsets; /1 is an erlang.erl library wrapper
%% whose compiled dispatch is a separate follow-up), so this fixture does NOT call them.
%%
%% Run on BOTH VMs (no stdlib needed — all erlang: BIFs):
%%   third_party/otp/bin/erlc -o OUT fixtures/erl/zigvm_localtime_diff.erl
%%   third_party/otp/bin/erl -noshell -pa OUT -eval 'zigvm_localtime_diff:t(0), init:stop().'
%%   zig-out/bin/zigvm run OUT/zigvm_localtime_diff.beam t 0
%% Byte-EQ verdict (both): {localtime_diff,summer_local,{{2024,6,15},{14,0,0}},
%%   winter_local,{{2023,12,25},{10,30,15}},decompose,true}
%% (the two conversion tuples are the HOST's zone; on a UTC host both equal their
%% input — still byte-EQ across the two VMs, which is what this asserts.)
-module(zigvm_localtime_diff).
-export([t/1]).
t(_) ->
    SummerUTC = {{2024, 6, 15}, {12, 0, 0}},
    WinterUTC = {{2023, 12, 25}, {9, 30, 15}},
    SummerLocal = erlang:universaltime_to_localtime(SummerUTC),
    WinterLocal = erlang:universaltime_to_localtime(WinterUTC),
    %% localtime/0 decomposes into date/0 + time/0 (shape + consistency)
    LT = erlang:localtime(),
    Decompose = case LT of
                    {{_, _, _}, {_, _, _}} -> element(1, LT) =:= erlang:date() andalso element(2, LT) =:= erlang:time();
                    _ -> false
                end,
    erlang:display({localtime_diff, summer_local, SummerLocal, winter_local, WinterLocal,
                    decompose, Decompose}).
