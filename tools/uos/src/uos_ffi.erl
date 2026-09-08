-module(uos_ffi).
-export([get_arguments/0, read_file/1, file_exists/1, file_size/1, matches_timestamp_format/1, file_contains/2, is_elf_binary/1, validate_mirage_probe_receipt/1, halt/1, run_command/3]).
-include_lib("kernel/include/file.hrl").

halt(Code) ->
    erlang:halt(Code).


get_arguments() ->
    Args = init:get_plain_arguments(),
    [case unicode:characters_to_binary(A) of
        B when is_binary(B) -> B;
        _ -> list_to_binary(A)
     end || A <- Args].

%% Repository root resolution.
%%
%% The CLI runs with cwd = tools/uos (see tools/uos-cli), so repository-relative
%% paths do not resolve directly. A fallback is therefore necessary. The previous
%% implementation hardcoded "/home/an/NAS-setup/uos", which meant every gate
%% measured the CANONICAL checkout no matter which workspace it ran in: from a
%% sibling workspace with no var/ at all, file_exists("var/km/...") returned true.
%%
%% Resolution order is now: UOS_REPO if the wrapper set it, else walk upwards
%% from cwd looking for the repository marker. Never a hardcoded path.
repo_root() ->
    case os:getenv("UOS_REPO") of
        false -> find_root(filename:absname("."));
        [] -> find_root(filename:absname("."));
        Root -> Root
    end.

find_root(Dir) ->
    Marker = filelib:is_dir(filename:join(Dir, ".jj"))
        orelse filelib:is_regular(filename:join(Dir, "AGENTS.md")),
    case Marker of
        true -> Dir;
        false ->
            Parent = filename:dirname(Dir),
            case Parent =:= Dir of
                true -> Dir;
                false -> find_root(Parent)
            end
    end.

resolve(Path) ->
    case file:read_file_info(Path) of
        {ok, _} -> {ok, Path};
        _ ->
            Rooted = filename:join([repo_root(), Path]),
            case file:read_file_info(Rooted) of
                {ok, _} -> {ok, Rooted};
                _ -> error
            end
    end.

%% Whole-file read through the same workspace-honest resolver. Returns <<>> when
%% the file is absent, so callers see empty content rather than a crash; every
%% caller treats empty as "nothing to verify", which is fail-closed.
read_file(Path) ->
    case resolve(Path) of
        {ok, P} ->
            case file:read_file(P) of
                {ok, Bin} -> Bin;
                _ -> <<>>
            end;
        error -> <<>>
    end.

file_exists(Path) ->
    case resolve(Path) of
        {ok, _} -> true;
        error -> false
    end.

file_size(Path) ->
    Info = case resolve(Path) of
        {ok, P} -> file:read_file_info(P);
        error -> error
    end,
    case Info of
        {ok, #file_info{size = Size}} -> Size;
        _ -> -1
    end.

matches_timestamp_format(Filename) ->
    case re:run(Filename, "^[0-9]{8}-[0-9]{4}-") of
        {match, _} -> true;
        _ -> false
    end.

file_contains(Path, Pattern) ->
    RealPath = case file:read_file(Path) of
        {ok, Bin} -> {ok, Bin};
        _ ->
            RootPath = filename:join([repo_root(), Path]),
            file:read_file(RootPath)
    end,
    case RealPath of
        {ok, Content} ->
            PatternBin = case is_list(Pattern) of
                true -> unicode:characters_to_binary(Pattern);
                false -> Pattern
            end,
            case binary:match(Content, PatternBin) of
                nomatch -> false;
                _ -> true
            end;
        _ -> false
    end.

is_elf_binary(Path) ->
    RealPath = case file:open(Path, [read, binary]) of
        {ok, Fd0} -> {ok, Fd0};
        _ ->
            RootPath = filename:join([repo_root(), Path]),
            file:open(RootPath, [read, binary])
    end,
    case RealPath of
        {ok, Fd} ->
            Res = case file:read(Fd, 4) of
                {ok, <<16#7F, $E, $L, $F>>} -> true;
                _ -> false
            end,
            file:close(Fd),
            Res;
        _ -> false
    end.

validate_mirage_probe_receipt(Path) ->
    RealPath = case file:read_file(Path) of
        {ok, B} -> {ok, B};
        _ ->
            RootPath = filename:join([repo_root(), Path]),
            file:read_file(RootPath)
    end,
    case RealPath of
        {ok, Bin} ->
            try
                M = json:decode(Bin),
                SchemaOk = (maps:get(<<"schema">>, M, <<>>) =:= <<"uos-mirage-hypervisor-probe/v1">>),
                HostOk = (maps:get(<<"host">>, M, <<>>) =:= <<"nas-1">>),
                OverallOk = (maps:get(<<"overall_readiness">>, M, <<>>) =:= <<"solo5_hardware_virtualized_and_spt_verified">>),
                Adm = maps:get(<<"deployment_admission">>, M, <<>>),
                AdmissionOk = (Adm =:= <<"TENDERS_VERIFIED_PHYSICAL_EXECUTION">>) orelse
                              (Adm =:= <<"TENDERS_VERIFIED_PHYSICAL_EXECUTION_DISJOINT_PROBE">>),
                ReviewStatus = maps:get(<<"codex_review_status">>, M, <<>>),
                ReviewOk = (ReviewStatus =:= <<"INDEPENDENT_EVALUATION_IN_PROGRESS">>),
                BootId = maps:get(<<"boot_id">>, M, <<>>),
                BootIdOk = byte_size(BootId) >= 32,
                TS = maps:get(<<"timestamp_utc">>, M, <<>>),
                NowSec = erlang:system_time(second),
                ReceiptSec = try calendar:rfc3339_to_system_time(binary_to_list(TS), [{unit, second}]) catch _:_ -> 0 end,
                TsOk = (ReceiptSec > 0) andalso (abs(NowSec - ReceiptSec) =< 86400 * 7),
                Kvm = maps:get(<<"kvm">>, M, #{}),
                KvmOk = (maps:get(<<"dev_kvm_present">>, Kvm, false) =:= true) andalso
                        (maps:get(<<"dev_kvm_rw_accessible">>, Kvm, false) =:= true) andalso
                        (maps:get(<<"api_version">>, Kvm, 0) >= 12),
                Qemu = maps:get(<<"qemu">>, M, #{}),
                QemuOk = (maps:get(<<"microvm_supported">>, Qemu, false) =:= true) andalso
                         (maps:get(<<"kvm_accel_supported">>, Qemu, false) =:= true),
                Solo5 = maps:get(<<"solo5">>, M, #{}),
                Hvt = maps:get(<<"hvt_execution">>, Solo5, #{}),
                HvtOk = (maps:get(<<"passed">>, Hvt, false) =:= true) andalso
                        (maps:get(<<"exit_code">>, Hvt, -1) =:= 0) andalso
                        (byte_size(maps:get(<<"tender_sha256">>, Hvt, <<>>)) =:= 64) andalso
                        (byte_size(maps:get(<<"unikernel_sha256">>, Hvt, <<>>)) =:= 64),
                Spt = maps:get(<<"spt_execution">>, Solo5, #{}),
                SptOk = (maps:get(<<"passed">>, Spt, false) =:= true) andalso
                        (maps:get(<<"exit_code">>, Spt, -1) =:= 0) andalso
                        (byte_size(maps:get(<<"tender_sha256">>, Spt, <<>>)) =:= 64) andalso
                        (byte_size(maps:get(<<"unikernel_sha256">>, Spt, <<>>)) =:= 64),
                Virtio = maps:get(<<"virtio_execution">>, Solo5, #{}),
                VirtioOk = (maps:get(<<"passed">>, Virtio, false) =:= true) andalso
                           (maps:get(<<"exit_code">>, Virtio, -1) =:= 83) andalso
                           (byte_size(maps:get(<<"tender_sha256">>, Virtio, <<>>)) =:= 64) andalso
                           (byte_size(maps:get(<<"unikernel_sha256">>, Virtio, <<>>)) =:= 64),
                SchemaOk andalso HostOk andalso OverallOk andalso AdmissionOk andalso
                ReviewOk andalso BootIdOk andalso TsOk andalso KvmOk andalso QemuOk andalso
                HvtOk andalso SptOk andalso VirtioOk
            catch
                _:_ -> false
            end;
        _ -> false
    end.




%% Bounded local command runner for gates that must observe execution, not file
%% presence. Runs Exe with Args from the repository root, merges stderr into
%% stdout, and returns {ExitCode, Output}. On TimeoutMs the port is closed and
%% exit code 124 is returned. No shell is involved.
run_command(Exe, Args, TimeoutMs) ->
    Root = repo_root(),
    ExeStr = binary_to_list(Exe),
    ArgStrs = [binary_to_list(A) || A <- Args],
    Resolved = case lists:member($/, ExeStr) of
        true ->
            Candidate = case ExeStr of
                [$/ | _] -> ExeStr;
                _ -> filename:join(Root, ExeStr)
            end,
            case filelib:is_regular(Candidate) of
                true -> Candidate;
                false -> false
            end;
        false -> os:find_executable(ExeStr)
    end,
    case Resolved of
        false -> {127, <<"executable not found">>};
        Path ->
            Port = erlang:open_port({spawn_executable, Path},
                                    [{args, ArgStrs}, {cd, Root}, exit_status,
                                     stderr_to_stdout, binary, use_stdio, hide]),
            collect(Port, <<>>, TimeoutMs)
    end.

collect(Port, Acc, TimeoutMs) ->
    receive
        {Port, {data, Bin}} -> collect(Port, <<Acc/binary, Bin/binary>>, TimeoutMs);
        {Port, {exit_status, Code}} -> {Code, Acc}
    after TimeoutMs ->
        catch erlang:port_close(Port),
        {124, <<Acc/binary, "\n[uos_ffi] timeout after ", (integer_to_binary(TimeoutMs))/binary, " ms\n">>}
    end.
