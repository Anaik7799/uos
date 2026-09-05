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
    case filelib:is_dir(FullPath) of
        true ->
            render_dir_listing(FullPath, CleanPath);
        false ->
            case file:read_file(FullPath) of
                {ok, Bin} -> {ok, Bin};
                {error, eisdir} ->
                    render_dir_listing(FullPath, CleanPath);
                {error, enoent} ->
                    %% Try adding .md extension
                    case file:read_file(FullPath ++ ".md") of
                        {ok, MdBin} -> {ok, MdBin};
                        _ ->
                            %% Search in directory for matching file prefix/substring
                            Dir = filename:dirname(FullPath),
                            Base = string:lowercase(filename:basename(FullPath)),
                            case file:list_dir(Dir) of
                                {ok, Files} ->
                                    Matching = [F || F <- Files,
                                        string:find(string:lowercase(F), Base) =/= nomatch],
                                    case Matching of
                                        [FirstMatch | _] ->
                                            file:read_file(filename:join([Dir, FirstMatch]));
                                        [] ->
                                            {error, <<"enoent">>}
                                    end;
                                _ ->
                                    {error, <<"enoent">>}
                            end
                    end;
                {error, Reason} ->
                    {error, list_to_binary(atom_to_list(Reason))}
            end
    end.

render_dir_listing(FullPath, CleanPath) ->
    case file:list_dir(FullPath) of
        {ok, Files} ->
            Sorted = lists:sort(Files),
            Lines = [
                "# Directory: /", CleanPath, "\n\n",
                "| Name | Type | Navigation Link |\n",
                "|---|---|---|\n"
            ] ++ [
                format_entry(CleanPath, FullPath, F) || F <- Sorted
            ],
            {ok, unicode:characters_to_binary(lists:flatten(Lines))};
        {error, Reason} ->
            {error, list_to_binary(atom_to_list(Reason))}
    end.

format_entry(CleanPath, FullPath, F) ->
    SubPath = filename:join([FullPath, F]),
    RelLink = case CleanPath of
        "" -> F;
        _ -> CleanPath ++ "/" ++ F
    end,
    Type = case filelib:is_dir(SubPath) of
        true -> "📁 Directory";
        false -> "📄 File"
    end,
    WebPath = case CleanPath of
        "docs/wiki" ++ _ -> "/wiki/" ++ F;
        "docs/zk" ++ _ -> "/zk/" ++ F;
        "docs" ++ _ ->
            PrefixLen = length("docs/"),
            case length(RelLink) >= PrefixLen of
                true -> "/docs/" ++ string:slice(RelLink, PrefixLen);
                false -> "/docs/" ++ RelLink
            end;
        _ -> "/files/" ++ RelLink
    end,
    ["| `", F, "` | ", Type, " | [", F, "](", WebPath, ") |\n"].

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
