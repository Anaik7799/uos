-module(mini_control_test_ffi).
-export([kill_actor/0]).
kill_actor() -> case whereis(uos_mini_development_control) of undefined -> nil; P -> exit(P,kill),nil end.
