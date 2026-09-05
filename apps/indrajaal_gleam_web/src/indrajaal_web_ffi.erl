-module(indrajaal_web_ffi).
-export([read_repo_file/1, list_repo_dir/1]).

read_repo_file(RelativePath) ->
    Root = "/home/an/NAS-setup/uos",
    PathStr = case is_binary(RelativePath) of
        true -> binary_to_list(RelativePath);
        false -> RelativePath
    end,
    CleanPath = case PathStr of
        "/" ++ Rest -> Rest;
        P -> P
    end,
    FullPath = filename:join([Root, CleanPath]),
    case file:read_file(FullPath) of
        {ok, Bin} -> {ok, Bin};
        {error, Reason} -> {error, list_to_binary(atom_to_list(Reason))}
    end.

list_repo_dir(RelativePath) ->
    Root = "/home/an/NAS-setup/uos",
    PathStr = case is_binary(RelativePath) of
        true -> binary_to_list(RelativePath);
        false -> RelativePath
    end,
    CleanPath = case PathStr of
        "/" ++ Rest -> Rest;
        P -> P
    end,
    FullPath = filename:join([Root, CleanPath]),
    case file:list_dir(FullPath) of
        {ok, Filenames} ->
            Bins = [unicode:characters_to_binary(F) || F <- Filenames],
            {ok, Bins};
        {error, Reason} -> {error, list_to_binary(atom_to_list(Reason))}
    end.
