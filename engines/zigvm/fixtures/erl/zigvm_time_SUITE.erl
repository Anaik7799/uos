%% zigvm_time_SUITE — a PURE curated subset of erts `time_SUITE`, in the
%% common_test SUITE shape, NO common_test / test_server dependency. Every case
%% drives the PURE Gregorian-arithmetic BIFs `erlang:universaltime_to_posixtime/1`
%% and `erlang:posixtime_to_universaltime/1` (both `.implemented` + EQ on zigvm,
%% bifs/conv.zig) over erts `time_SUITE`'s own `ok_utc_seconds/0` datetime↔posix
%% pairs — spanning the 1970 epoch, pre-epoch negatives, the Sint32/Uint32
%% boundaries (2038/2106), and far future/past (1600/2412). These conversions are
%% timezone-INDEPENDENT and value-stable, so both VMs compute them bit-identically.
%% The timezone-DEPENDENT cases of the real suite (local_to_univ/univ_to_local,
%% consistency, now()/date()/time()) are EXCLUDED — those ride the deferred wall-
%% clock/TZ surface (never a false EQ). Datetimes/seconds travel through
%% `?MODULE:id/1` so the compiler cannot fold the operand out of the VM.
-module(zigvm_time_SUITE).

-export([all/0,
         c_epoch/1, c_pre_epoch/1, c_sint32_boundary/1, c_uint32_boundary/1,
         c_far/1, c_roundtrip/1,
         id/1]).

all() ->
    [c_epoch, c_pre_epoch, c_sint32_boundary, c_uint32_boundary,
     c_far, c_roundtrip].

id(X) -> X.

%% both directions byte-EQ for one {Datetime, Seconds} pair.
both(DT, S) ->
    (erlang:universaltime_to_posixtime(id(DT)) =:= S)
        andalso (erlang:posixtime_to_universaltime(id(S)) =:= DT).

%% --- the 1970 epoch neighbourhood --------------------------------------------
c_epoch(_) ->
    both({{1970, 1, 1}, {0, 0, 0}}, 0)
        andalso both({{1970, 1, 1}, {0, 0, 1}}, 1)
        andalso both({{2000, 1, 1}, {0, 0, 0}}, 946684800)
        andalso both({{1999, 12, 31}, {23, 59, 59}}, 946684799).

%% --- pre-epoch (negative posix seconds) --------------------------------------
c_pre_epoch(_) ->
    both({{1969, 12, 31}, {23, 59, 59}}, -1)
        andalso both({{1920, 12, 31}, {23, 59, 59}}, -1546300801).

%% --- the signed-32-bit second boundary (2038) --------------------------------
c_sint32_boundary(_) ->
    both({{2038, 1, 19}, {3, 14, 7}}, 2147483647)
        andalso both({{2038, 1, 19}, {3, 14, 8}}, 2147483648)
        andalso both({{2038, 1, 19}, {3, 14, 9}}, 2147483649).

%% --- the unsigned-32-bit second boundary (2106) ------------------------------
c_uint32_boundary(_) ->
    both({{2106, 2, 7}, {6, 28, 14}}, 4294967294)
        andalso both({{2106, 2, 7}, {6, 28, 15}}, 4294967295)
        andalso both({{2106, 2, 7}, {6, 28, 16}}, 4294967296).

%% --- far past / future -------------------------------------------------------
c_far(_) ->
    both({{1600, 2, 19}, {15, 14, 8}}, -11671807552)
        andalso both({{2412, 12, 6}, {16, 28, 8}}, 13977592088)
        andalso both({{2012, 12, 6}, {16, 28, 8}}, 1354811288)
        andalso both({{1979, 5, 28}, {12, 30, 35}}, 296742635).

%% --- round-trip: posix→univ→posix is the identity ----------------------------
c_roundtrip(_) ->
    RT = fun(S) -> erlang:universaltime_to_posixtime(id(erlang:posixtime_to_universaltime(id(S)))) =:= S end,
    RT(0) andalso RT(1) andalso RT(-1) andalso RT(946684800)
        andalso RT(2147483648) andalso RT(4294967296) andalso RT(13977592088).
