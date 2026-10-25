-module(telegram_ecology_clock).
-export([now_ms/0]).
now_ms() -> erlang:system_time(millisecond).
