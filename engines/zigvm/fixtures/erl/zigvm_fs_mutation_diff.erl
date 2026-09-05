%% zigvm_fs_mutation_diff — the filesystem-mutation differential (gap-file-fs-mutation,
%% DIVERGENCE 590). file:delete/rename/make_dir/del_dir/truncate/sync + read_link_info,
%% ok/{error,Posix} shapes byte-identical on pinned OTP-30 and zigvm. Run each from
%% its OWN fresh CWD (the ops mutate the fs):  erl -run zigvm_fs_mutation_diff g  /
%%  zigvm run f.beam g.  (The FINAL file: slice — real_file_io is EQ.)
-module(zigvm_fs_mutation_diff).
-export([g/0]).
g() ->
    file:write_file("fm_d.dat", <<"x">>),
    erlang:display({delete_ok, file:delete("fm_d.dat")}),
    erlang:display({delete_enoent, file:delete("fm_nope.dat")}),
    file:write_file("fm_r1.dat", <<"y">>),
    erlang:display({rename_ok, file:rename("fm_r1.dat", "fm_r2.dat")}),
    erlang:display({rename_enoent, file:rename("fm_nope.dat", "fm_r3.dat")}),
    file:del_dir("fm_sub"),
    erlang:display({make_dir_ok, file:make_dir("fm_sub")}),
    erlang:display({make_dir_eexist, file:make_dir("fm_sub")}),
    erlang:display({del_dir_ok, file:del_dir("fm_sub")}),
    erlang:display({del_dir_enoent, file:del_dir("fm_nope")}),
    file:write_file("fm_t.dat", <<"0123456789">>),
    {ok, TF} = file:open("fm_t.dat", [read, write, raw, binary]),
    {ok, 4} = file:position(TF, 4),
    erlang:display({truncate_ok, file:truncate(TF)}),
    file:close(TF),
    erlang:display({after_trunc, file:read_file("fm_t.dat")}),
    {ok, SF} = file:open("fm_s.dat", [write, raw]),
    erlang:display({sync_ok, file:sync(SF)}),
    file:close(SF),
    erlang:display({rli_type, element(3, element(2, file:read_link_info("fm_t.dat", [{time,posix}])))}),
    halt(0).
