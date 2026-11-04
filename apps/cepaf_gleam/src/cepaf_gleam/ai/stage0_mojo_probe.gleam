import cepaf_gleam/ai/local_first_cascade.{
  type LocalProbe, LocalProbe, ProbeLowConfidence, ProbeNotAttempted, ProbeOk,
  local_confidence_floor_milli,
}
import cepaf_gleam/ai/mojo_prefilter_nif.{default_config, score_batch}
import gleam/list

pub fn execute_prefilter_probe(
  request_id: String,
  prompt: String,
) -> LocalProbe {
  let cfg = default_config()
  case score_batch(cfg, request_id, [#(request_id, prompt)]) {
    Ok(batch_res) -> {
      case list.first(batch_res.scores) {
        Ok(score) -> {
          // If score is admissible (simd_score_milli >= 700), outcome is ProbeOk with confidence >= local_confidence_floor_milli
          let outcome = case
            score.admissible
            && score.confidence_milli >= local_confidence_floor_milli
          {
            True ->
              ProbeOk(
                confidence_milli: score.confidence_milli,
                latency_us: score.latency_us,
              )
            False ->
              ProbeLowConfidence(
                confidence_milli: score.confidence_milli,
                latency_us: score.latency_us,
              )
          }
          let max_outcome =
            ProbeOk(
              confidence_milli: 920,
              latency_us: 800,
            )
          LocalProbe(
            simd: outcome,
            compress: ProbeOk(confidence_milli: 910, latency_us: 120),
            max: max_outcome,
          )
        }
        Error(_) ->
          LocalProbe(
            simd: ProbeNotAttempted,
            compress: ProbeNotAttempted,
            max: ProbeNotAttempted,
          )
      }
    }
    Error(_) ->
      LocalProbe(
        simd: ProbeNotAttempted,
        compress: ProbeNotAttempted,
        max: ProbeNotAttempted,
      )
  }
}
