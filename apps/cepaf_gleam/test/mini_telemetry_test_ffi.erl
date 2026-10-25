-module(mini_telemetry_test_ffi).
-export([kill_collector/0,wait_collector/0]).
kill_collector() ->
  P=whereis(uos_telegram_mini_telemetry),
  true=is_pid(P), R=erlang:monitor(process,P), exit(P,kill),
  receive {'DOWN',R,process,P,_}->nil after 1000->error(kill_timeout) end.
wait_collector() -> wait_collector(100).
wait_collector(0) -> error(restart_timeout);
wait_collector(N) ->
  case whereis(uos_telegram_mini_telemetry) of
    undefined -> timer:sleep(5),wait_collector(N-1);
    _ -> nil
  end.
