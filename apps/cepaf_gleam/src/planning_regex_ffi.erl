-module(planning_regex_ffi).
-export([main_todo_regex/0, priority_regex/0]).

main_todo_regex() ->
    {ok, MP} = re:compile(<<"^##\\s*([\\d\\.]+)\\s*-\\s*(.*?)\\s*\\[(.*?)\\]$">>, [unicode, ucp]),
    MP.

priority_regex() ->
    {ok, MP} = re:compile(<<"\\((P\\d)\\)">>, [unicode, ucp]),
    MP.
