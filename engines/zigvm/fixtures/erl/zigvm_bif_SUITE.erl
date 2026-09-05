-module(zigvm_bif_SUITE).
-export([all/0, c_min_max/1, c_test_length/1, c_is_builtin/1, c_records_get_definition/1]).
all() -> [c_min_max, c_test_length, c_is_builtin, c_records_get_definition].
c_min_max(_) -> max(1, 2) =:= 2 andalso min(1, 2) =:= 1.
c_test_length(_) -> length([1,2,3]) =:= 3.
c_is_builtin(_) -> erlang:is_builtin(erlang, length, 1).
c_records_get_definition(_) -> true.
