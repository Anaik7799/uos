-module(zigvm_phash2_atom_diff).
-export([t/1]).
%% phash2 of atoms, BY VALUE (list of integer hashes — no char-list ambiguity)
t(_) -> [erlang:phash2(A) || A <- [hello,world,ok,error,undefined,false,true,foo,'Bar']].
