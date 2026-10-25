%%% Initial encoding (deep embedding): terms as tagged tuples — the oracle.
%%% Correct by construction: the interpreter clauses ARE the [[.]] equations.
-module(canvas_initial).
-behaviour(canvas_algebra).
-export([empty/0, fill/1, overlay/2, rasterize/1, eql/2]).

-type canvas() :: empty
                | {fill, canvas_algebra:pixel()}
                | {overlay, canvas(), canvas()}.
-export_type([canvas/0]).

-spec empty() -> canvas().
empty() -> empty.

-spec fill(canvas_algebra:pixel()) -> canvas().
fill(Px) -> {fill, Px}.

-spec overlay(canvas(), canvas()) -> canvas().
overlay(Top, Bottom) -> {overlay, Top, Bottom}.

%% The observation: fold the term into the semantic domain.
%% Exhaustive over the domain's variants — deliberately NO catch-all clause;
%% adding a variant makes unhandled interpreters crash loudly (let it crash),
%% and dialyzer flags the gap statically.
-spec rasterize(canvas()) -> canvas_algebra:raster().
rasterize(empty)            -> canvas_algebra:blank();
rasterize({fill, Px})       -> canvas_algebra:uniform(Px);
rasterize({overlay, T, B})  -> canvas_algebra:over(rasterize(T), rasterize(B)).

%% Observational equality (doctrine rule 1): compare denotations, never terms.
-spec eql(canvas(), canvas()) -> boolean().
eql(A, B) -> canvas_algebra:raster_eql(rasterize(A), rasterize(B)).
