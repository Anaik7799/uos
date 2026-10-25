-module(telegram_budget_clock).
-export([now_us/0,monotonic_ms/0,utc_day/1]).
now_us()->erlang:system_time(microsecond).
monotonic_ms()->erlang:monotonic_time(millisecond).
utc_day(Us) when is_integer(Us), Us>0, Us=<8000000000000000 ->
 {{Y,M,D},_}=calendar:system_time_to_universal_time(Us,microsecond),
 iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0B",[Y,M,D]));
utc_day(_)-> <<>>.
