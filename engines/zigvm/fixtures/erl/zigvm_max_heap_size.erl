%% gap-atom-and-heap-limits: process_flag(max_heap_size, _) config round-trip,
%% byte-EQ vs OTP-30. Displays the OLD (default) map then the read-back.
-module(zigvm_max_heap_size).
-export([t/1]).
t(_) ->
    Old = process_flag(max_heap_size, 1000000),
    erlang:display({old, Old}),
    Cur = process_flag(max_heap_size, 0),
    erlang:display({read_back_size, maps:get(size, Cur)}),
    erlang:display({neg_badarg, (catch process_flag(max_heap_size, -1)) =:= badarg
                                orelse element(1, element(2, (catch process_flag(max_heap_size, -1)))) =:= badarg}),
    ok.
