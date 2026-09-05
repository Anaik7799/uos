-module(zigvm_concurrency_SUITE).
-export([all/0, c_self_signal/1, c_advanced_monitor/1]).
all() -> [c_self_signal, c_advanced_monitor].
c_self_signal(_) -> true.
c_advanced_monitor(_) -> true.
