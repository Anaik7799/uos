%% zigvm_io_format_diff — the io:format BINARY differential fixture
%% (gap-io-format-binary). Renders ~w/~p/~s/~P of binaries; the output is
%% byte-identical on pinned OTP-30 and on zigvm's native io_lib:format
%% interpreter (src/bifs/io_format.zig). Manual sequential calls (no lists:*)
%% so it runs on zigvm with NO --code-path. Run:
%%   erlc -o D f.erl; erl -noshell -pa D -run zigvm_io_format_diff main
%%   zig-out/bin/zigvm run f.beam main
%% and diff (strip the trailing run-harness line + CR: `tr -d '\r'`, drop the
%% last line which is OTP-absent / zigvm's function return value).
-module(zigvm_io_format_diff).
-export([main/0]).

main() ->
    io:format("~w~n", [<<"ping">>]),                 % <<112,105,110,103>>
    io:format("~w~n", [<<>>]),                       % <<>>
    io:format("~w~n", [<<1,2,3>>]),                  % <<1,2,3>>
    io:format("~p~n", [<<"ping">>]),                 % <<"ping">>
    io:format("~p~n", [<<>>]),                       % <<>>
    io:format("~p~n", [<<1,2,3>>]),                  % <<1,2,3>>
    io:format("~p~n", [<<"ab",1>>]),                 % <<97,98,1>>
    io:format("~p~n", [<<"has \"q\" \\bs">>]),        % escaping
    io:format("~p~n", [<<"tab\ttab">>]),             % <<"tab\ttab">>
    io:format("~s~n", [<<"ping">>]),                 % ping
    io:format("~s~n", [<<>>]),                        % (empty)
    io:format("~p~n", [{nested, <<"bin">>, [<<1>>]}]),% {nested,<<"bin">>,[<<1>>]}
    io:format("~P~n", [<<"ping">>, 1]),              % <<...>>
    io:format("~P~n", [<<"ping">>, 2]),              % <<"ping">>
    halt(0).                                          % clean exit on both (halt now wired: DIVERGENCE 584)
