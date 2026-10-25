import gleam/option.{type Option, None, Some}
import gleam/string

pub const snapshot_interval_us = 300_000_000

pub type State {
  State(last_snapshot_boot_us: Int, completion_marker: String)
}

pub fn due(
  now_boot_us: Int,
  marker: String,
  previous: Option(State),
) -> Result(Bool, String) {
  case now_boot_us < 0, string.is_empty(string.trim(marker)) {
    True, _ -> Error("now_boot_us must be non-negative")
    False, True -> Error("completion_marker must not be empty")
    False, False ->
      case previous {
        None -> Ok(True)
        Some(State(last_snapshot_boot_us, completion_marker)) ->
          case
            last_snapshot_boot_us < 0,
            string.is_empty(string.trim(completion_marker)),
            now_boot_us < last_snapshot_boot_us
          {
            True, _, _ -> Error("last_snapshot_boot_us must be non-negative")
            False, True, _ -> Error("prior completion_marker must not be empty")
            False, False, True -> Error("clock moved backward")
            False, False, False -> {
              let elapsed_us = now_boot_us - last_snapshot_boot_us
              Ok(
                elapsed_us >= snapshot_interval_us
                || marker != completion_marker,
              )
            }
          }
      }
  }
}
