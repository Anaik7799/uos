%% eco_datetime — a reduced ecosystem app exercising the `calendar` and `timer`
%% modules zigvm now hosts via the preloaded stock stdlib (gap-hof-datetime,
%% DIVERGENCE 669). Both are Erlang code, not BIFs — undef before this slice.
%%
%% Run as `zigvm run eco_datetime.beam suite`. HONESTY BOUNDS: only the
%% DETERMINISTIC calendar date/time math is asserted (day_of_the_week/valid_date/
%% gregorian days & seconds/leap-year/differences) — NEVER the TZ/host-dependent
%% functions (local_time/universal_time). For timer, only the PURE conversion
%% helpers + sleep are asserted — NEVER timer:tc (nondeterministic timing) nor
%% the server-based fns (apply_after/send_after need a running timer_server
%% gen_server — a separate gap).
-module(eco_datetime).
-export([suite/0]).

suite() ->
    %% calendar — deterministic date/time math.
    C1  = (calendar:day_of_the_week(2026, 7, 30) =:= 4),
    C2  = (calendar:day_of_the_week({2000, 1, 1}) =:= 6),
    C3  = ({calendar:valid_date(2024, 2, 29), calendar:valid_date(2025, 2, 29), calendar:valid_date(2024, 13, 1)} =:= {true, false, false}),
    C4  = (calendar:is_leap_year(2024)) andalso (not calendar:is_leap_year(2100)) andalso (calendar:is_leap_year(2000)),
    C5  = (calendar:last_day_of_the_month(2024, 2) =:= 29),
    C6  = (calendar:last_day_of_the_month(2025, 2) =:= 28),
    D   = calendar:date_to_gregorian_days(2026, 7, 30),
    C7  = (D =:= 740192),
    C8  = (calendar:gregorian_days_to_date(D) =:= {2026, 7, 30}),
    Sec = calendar:datetime_to_gregorian_seconds({{2026, 7, 30}, {12, 0, 0}}),
    C9  = (calendar:gregorian_seconds_to_datetime(Sec) =:= {{2026, 7, 30}, {12, 0, 0}}),
    C10 = (calendar:time_difference({{2026, 1, 1}, {0, 0, 0}}, {{2026, 1, 2}, {6, 0, 0}}) =:= {1, {6, 0, 0}}),
    C11 = (calendar:seconds_to_daystime(90061) =:= {1, {1, 1, 1}}),
    C12 = (calendar:seconds_to_time(3661) =:= {1, 1, 1}),
    C13 = (calendar:time_to_seconds({1, 1, 1}) =:= 3661),
    C14 = (calendar:date_to_gregorian_days({2000, 1, 1}) - calendar:date_to_gregorian_days({1999, 1, 1}) =:= 365),

    %% timer — PURE helpers only (server-based fns are a separate gap).
    C15 = (timer:hms(1, 2, 3) =:= 3723000),
    C16 = (timer:hours(2) =:= 7200000),
    C17 = (timer:minutes(5) =:= 300000),
    C18 = (timer:seconds(30) =:= 30000),
    C19 = (timer:sleep(1) =:= ok),

    case
        C1 andalso C2 andalso C3 andalso C4 andalso C5 andalso C6 andalso C7
        andalso C8 andalso C9 andalso C10 andalso C11 andalso C12 andalso C13
        andalso C14 andalso C15 andalso C16 andalso C17 andalso C18 andalso C19
    of
        true -> ok;
        false -> fail
    end.
