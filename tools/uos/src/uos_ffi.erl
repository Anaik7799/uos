-module(uos_ffi).
-export([get_arguments/0, file_exists/1, file_size/1, matches_timestamp_format/1, file_contains/2, is_elf_binary/1, validate_mirage_probe_receipt/1, halt/1]).
-include_lib("kernel/include/file.hrl").

halt(Code) ->
    erlang:halt(Code).


get_arguments() ->
    Args = init:get_plain_arguments(),
    [case unicode:characters_to_binary(A) of
        B when is_binary(B) -> B;
        _ -> list_to_binary(A)
     end || A <- Args].

file_exists(Path) ->
    case file:read_file_info(Path) of
        {ok, _} -> true;
        _ ->
            RootPath = filename:join(["/home/an/NAS-setup/uos", Path]),
            case file:read_file_info(RootPath) of
                {ok, _} -> true;
                _ -> false
            end
    end.

file_size(Path) ->
    Info = case file:read_file_info(Path) of
        {ok, I} -> {ok, I};
        _ ->
            RootPath = filename:join(["/home/an/NAS-setup/uos", Path]),
            file:read_file_info(RootPath)
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
            RootPath = filename:join(["/home/an/NAS-setup/uos", Path]),
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
            RootPath = filename:join(["/home/an/NAS-setup/uos", Path]),
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
            RootPath = filename:join(["/home/an/NAS-setup/uos", Path]),
            file:read_file(RootPath)
    end,
    case RealPath of
        {ok, Bin} ->
            try
                M = json:decode(Bin),
                SchemaOk = (maps:get(<<"schema">>, M, <<>>) =:= <<"uos-mirage-hypervisor-probe/v1">>),
                HostOk = (maps:get(<<"host">>, M, <<>>) =:= <<"nas-1">>),
                OverallOk = (maps:get(<<"overall_readiness">>, M, <<>>) =:= <<"solo5_hardware_virtualized_and_spt_verified">>),
                AdmissionOk = (maps:get(<<"deployment_admission">>, M, <<>>) =:= <<"TENDERS_VERIFIED_PHYSICAL_EXECUTION">>),
                TS = maps:get(<<"timestamp_utc">>, M, <<>>),
                TsOk = (binary:longest_common_prefix([TS, <<"2026">>]) =:= 4),
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
                        (maps:get(<<"exit_code">>, Hvt, -1) =:= 0),
                Spt = maps:get(<<"spt_execution">>, Solo5, #{}),
                SptOk = (maps:get(<<"passed">>, Spt, false) =:= true) andalso
                        (maps:get(<<"exit_code">>, Spt, -1) =:= 0),
                Virtio = maps:get(<<"virtio_execution">>, Solo5, #{}),
                VirtioOk = (maps:get(<<"passed">>, Virtio, false) =:= true) andalso
                           (maps:get(<<"exit_code">>, Virtio, -1) =:= 83),
                SchemaOk andalso HostOk andalso OverallOk andalso AdmissionOk andalso
                TsOk andalso KvmOk andalso QemuOk andalso HvtOk andalso SptOk andalso VirtioOk
            catch
                _:_ -> false
            end;
        _ -> false
    end.


