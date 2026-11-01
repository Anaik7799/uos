%% Erlang side of the merge-classifier oracle.
%%
%% Drives the DEPLOYED
%% apps/cepaf_gleam/src/cepaf_gleam/ui/wisp/inference_api.gleam
%% evaluate_ruliad_branch/4 and max_inference_daemon:is_ruliad_mergeable/1,
%% printing the same canonical format as ServiceDiff.lean.
-module(service_diff).
-export([run/1]).

run([Path]) ->
    io:setopts([{encoding, unicode}]),
    {ok, Bin} = file:read_file(Path),
    lists:foreach(
      fun(L) ->
          case is_blank(L) of
              true -> ok;
              false -> io:format("~ts~n", [case_line(L)])
          end
      end, binary:split(Bin, <<"\n">>, [global])),
    halt(0).

is_blank(B) ->
    binary:replace(B, [<<" ">>, <<"\r">>, <<"\t">>], <<>>, [global]) =:= <<>>.

split_field(<<>>) -> [];
split_field(B) -> binary:split(B, <<"|">>, [global]).

case_line(L) ->
    [Src, Tgt, Changes, Agents] = binary:split(L, <<"\t">>, [global]),
    R = 'cepaf_gleam@ui@wisp@inference_api':evaluate_ruliad_branch(
          Src, Tgt, split_field(Changes), split_field(Agents)),
    {ruliad_branch_report, Id, _Status, _Src, _Tgt, _Dist, _Sim, Entropy,
     _Conflict, Conv, ParticipatingAgents, Path, _Latency} = R,
    Mergeable = 'cepaf_gleam@services@max_inference_daemon':is_ruliad_mergeable(R),
    EntropyLt = Entropy < 2.5,
    [Src, <<"\t">>, Tgt, <<"\t">>, Changes, <<"\t">>, Agents, <<"\t">>,
     <<"status=">>, Conv,
     <<" mergeable=">>, atom_to_binary(Mergeable, utf8),
     <<" entropy_lt_gate=">>, atom_to_binary(EntropyLt, utf8),
     <<" id=">>, Id,
     <<" path=">>, join(Path, <<"/">>),
     <<" agents=">>, join(ParticipatingAgents, <<"/">>)].

join([], _) -> [];
join([X], _) -> [X];
join([X | Rest], Sep) -> [X, Sep | join(Rest, Sep)].
