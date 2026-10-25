%% Thin exception/timeout adapters only; policy and state remain in Gleam.
-module(mini_telemetry_ffi).
-export([safe_call/1, protect_backend/1, logger_level/0]).
safe_call(F) when is_function(F,0) ->
  uos_openrouter_ffi:bounded_call(fun(_) ->
    try {ok,F()} catch _:_ -> {error,<<"telemetry_unavailable">>} end
  end,100).
protect_backend(F) when is_function(F,0) ->
  try {ok,F()} catch _:_ -> {error,nil} end.
logger_level() ->
  safe_call(fun() ->
    #{level:=Level}=logger:get_primary_config(),
    atom_to_binary(Level,utf8)
  end).
