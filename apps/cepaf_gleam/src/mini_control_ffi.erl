-module(mini_control_ffi).
-export([safe_call/1, change_logger/2]).
safe_call(F) ->
  try {ok,F()} catch _:_ -> {error,nil} end.
%% The Gleam actor serializes its own operations. Other logger writers are not
%% covered by this compare/read/set; this is explicitly NOT a global atomic CAS.
change_logger(Expected, Target) ->
  Levels = [{<<"emergency">>,emergency},{<<"alert">>,alert},{<<"critical">>,critical},
    {<<"error">>,error},{<<"warning">>,warning},{<<"notice">>,notice},
    {<<"info">>,info},{<<"debug">>,debug},{<<"all">>,all},{<<"none">>,none}],
  case {lists:keyfind(Expected,1,Levels),lists:keyfind(Target,1,Levels)} of
    {{_,E},{_,T}} ->
      try
        case maps:get(level,logger:get_primary_config()) of
          E ->
            case logger:set_primary_config(level,T) of
              ok -> case maps:get(level,logger:get_primary_config()) of
                T -> {ok,{Expected,Target}};
                _ -> {error,<<"readback_uncertain">>}
              end;
              _ -> {error,<<"effect_uncertain">>}
            end;
          _ -> {error,<<"level_mismatch">>}
        end
      catch _:_ -> {error,<<"effect_uncertain">>} end;
    _ -> {error,<<"invalid_level">>}
  end.
