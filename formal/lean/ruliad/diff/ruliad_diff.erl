%% Erlang side of the model-to-source differential oracle.
%%
%% Drives the DEPLOYED Gleam engine
%% apps/cepaf_gleam/src/cepaf_gleam/ecology/multiway.gleam over the shared
%% corpus and prints the same canonical format as the Lean executable
%% formal/lean/ruliad/RuliadDiff.lean. Any difference between the two outputs
%% is a real model-to-source divergence.
%%
%% Erlang, not shell/Python/Node: the BEAM is where the subject under test
%% lives, so the harness calls it directly rather than through a wrapper.
-module(ruliad_diff).
-export([run/1]).

run([Path]) ->
    io:setopts([{encoding, unicode}]),
    {ok, Bin} = file:read_file(Path),
    Lines = binary:split(Bin, <<"\n">>, [global]),
    lists:foreach(
      fun(L) ->
          case is_blank(L) of
              true -> ok;
              false -> io:format("~ts~n", [case_line(L)])
          end
      end, Lines),
    halt(0).

is_blank(B) ->
    binary:replace(B, [<<" ">>, <<"\r">>, <<"\t">>], <<>>, [global]) =:= <<>>.

digits(B) ->
    L = [C || <<C>> <= B, C >= $0, C =< $9],
    case L of
        [] -> 0;
        _  -> binary_to_integer(list_to_binary(L))
    end.

parse_rules(<<>>) -> [];
parse_rules(Spec) ->
    [ begin
          case binary:split(S, <<">">>, [global]) of
              [From, To] -> {rule, From, To};
              _          -> {rule, S, <<>>}
          end
      end || S <- binary:split(Spec, <<",">>, [global]) ].

case_line(L) ->
    [Seed, RuleSpec, StepsRaw] = binary:split(L, <<"\t">>, [global]),
    Steps = digits(StepsRaw),
    Rules = parse_rules(RuleSpec),
    V = case 'cepaf_gleam@ecology@multiway':explore(Seed, Rules, Steps) of
            {ok, {graph, States, Edges, Frontier, S}} ->
                render(States, Edges, Frontier, S);
            {error, E} ->
                [<<"ERR ">>, E]
        end,
    [Seed, <<"\t">>, RuleSpec, <<"\t">>, integer_to_binary(Steps), <<"\t">>, V].

render(States, Edges, Frontier, S) ->
    [<<"OK states=[">>, join(States), <<"] edges=[">>,
     join([ [Src, <<">">>, Tgt, <<"@">>, integer_to_binary(R), <<":">>,
             integer_to_binary(O)] || {edge, Src, Tgt, R, O} <- Edges ]),
     <<"] frontier=[">>, join(Frontier), <<"] steps=">>, integer_to_binary(S)].

join([]) -> [];
join([X]) -> [X];
join([X | Rest]) -> [X, <<",">> | join(Rest)].
