%%% Final encoding (shallow embedding): a canvas IS its denotation.
%%% Derived from the semantic domain — operations compute eagerly; O(1) eql.
-module(canvas_final).
-behaviour(canvas_algebra).
-export([empty/0, fill/1, overlay/2, rasterize/1, eql/2]).

-type canvas() :: canvas_algebra:raster().
-export_type([canvas/0]).

-spec empty() -> canvas().
empty() -> canvas_algebra:blank().

-spec fill(canvas_algebra:pixel()) -> canvas().
fill(Px) -> canvas_algebra:uniform(Px).

-spec overlay(canvas(), canvas()) -> canvas().
overlay(Top, Bottom) -> canvas_algebra:over(Top, Bottom).

-spec rasterize(canvas()) -> canvas_algebra:raster().
rasterize(R) -> R.

-spec eql(canvas(), canvas()) -> boolean().
eql(A, B) -> canvas_algebra:raster_eql(A, B).
