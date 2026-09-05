%% E3.12b: a DEPENDENCY module for the cross-module `--pa` corpus cases. Its
%% helpers are reached from corpus_seed via fully-qualified calls (call_ext),
%% which the multi-beam linker resolves ACROSS separately-compiled .beam files
%% (corpus_seed.beam entry + corpus_dep.beam passed as `--pa`). A correct result
%% proves the linker concatenated + relocated the two modules into one code
%% space with a shared atom table and export index.
-module(corpus_dep).
-export([helper/1, add/2, chain/1]).

helper(X) -> X * 3 + 1.
add(A, B) -> A + B.
chain(X) -> helper(add(X, 10)).
