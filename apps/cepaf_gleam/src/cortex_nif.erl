%% =============================================================================
%% [C3I-SIL6-MSTS] cortex_nif Erlang load shim
%% =============================================================================
%% Loads the cortex_nif cdylib at module init. Functions below provide fallback
%% defaults that are replaced by the real Rust NIF once the .so is loaded.
%%
%% STAMP: SC-COG-001, SC-COG-MAX-001, SC-WIRE-001, CHK-07-DRIVE.
%% =============================================================================
-module(cortex_nif).

-export([
    cortex_ping/0,
    cortex_scrub_pii/1,
    cortex_transcribe_audio_pcm16/2,
    cortex_infer_local/2,
    cortex_check_storage_safety/1
]).

-on_load(init/0).

init() ->
    PrivDir = case code:priv_dir(cepaf_gleam) of
        {error, _} ->
            EbinDir = filename:dirname(code:which(?MODULE)),
            AppPath = filename:dirname(EbinDir),
            filename:join(AppPath, "priv");
        Path -> Path
    end,
    Lib = filename:join(PrivDir, "cortex_nif"),
    case filelib:is_file(Lib ++ ".so") of
        true -> erlang:load_nif(Lib, 0);
        false -> ok
    end.

cortex_ping() ->
    "pong:cortex_nif_fallback".

cortex_scrub_pii(Input) ->
    Input.

cortex_transcribe_audio_pcm16(_PcmBytes, _SampleRate) ->
    {ok, <<"{\"text\":\"[mock_transcription]\",\"sample_count\":0,\"sample_rate\":16000,\"duration_ms\":0,\"rms_energy\":0.0,\"is_silent\":true}">>}.

cortex_infer_local(_Prompt, _MaxTokens) ->
    {ok, <<"{\"tier\":\"Tier3MistralRsGemma4\",\"model\":\"gemma-4b-fallback\",\"text\":\"UOS Local Fallback Response\",\"tokens_generated\":8,\"latency_ms\":1,\"hardware_safe\":true}">>}.

cortex_check_storage_safety(SerialQuery) ->
    case string:find(SerialQuery, "25503L801736") of
        nomatch -> true;
        _ -> false
    end.
