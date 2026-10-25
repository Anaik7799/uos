-module(mini_boundary_test_ffi).
-export([set_clock/1,clock/0]).
set_clock(Times) -> put(mini_test_clock,Times), nil.
clock() -> case get(mini_test_clock) of [T|Rest] -> put(mini_test_clock,Rest), T; _ -> 1000 end.
