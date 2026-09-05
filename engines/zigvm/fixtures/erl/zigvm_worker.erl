%% http-laneC supervisor verify: the gen_server child of zigvm_sup. DIVERGENCE 639.
-module(zigvm_worker).
-behaviour(gen_server).
-export([start_link/0, init/1, handle_call/3, handle_cast/2]).
start_link() -> gen_server:start_link(?MODULE, [], []).
init([]) -> {ok, 0}.
handle_call(get, _F, N) -> {reply, N, N}.
handle_cast(_, N) -> {noreply, N}.
