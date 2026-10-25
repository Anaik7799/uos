import cepaf_gleam/harness/telegram_http_client.{
  type TelegramHttpConfiguration, TelegramHttpConfiguration,
} as client
import gleam/string

fn fixture_config(
  timeout_ms: Int,
  max_response_bytes: Int,
) -> TelegramHttpConfiguration {
  TelegramHttpConfiguration(
    base_url: "http://nas-1.tail55d152.ts.net:1",
    bot_token: "secret_token_never_leak",
    timeout_ms: timeout_ms,
    max_response_bytes: max_response_bytes,
  )
}

pub fn default_configuration_valid_test() {
  let config =
    client.default_configuration("http://nas-1.tail55d152.ts.net:1", "secret_token_never_leak")

  assert client.validate_poll_configuration(config, 10, 5) == Ok(Nil)
}

pub fn zero_poll_exact_1000ms_margin_test() {
  let exact_margin_config = fixture_config(1000, 1)
  assert client.validate_poll_configuration(exact_margin_config, 1, 0)
    == Ok(Nil)

  let max_bounds_zero_poll = fixture_config(60_000, 10_485_760)
  assert client.validate_poll_configuration(max_bounds_zero_poll, 1, 0)
    == Ok(Nil)

  let below_margin_config = fixture_config(999, 65_536)
  assert client.validate_poll_configuration(below_margin_config, 1, 0)
    == Error(
      "invalid_poll_config: http_timeout_ms_insufficient_for_poll_margin",
    )
}

pub fn poll_5s_http_6000ms_valid_test() {
  let config = fixture_config(6000, 65_536)
  assert client.validate_poll_configuration(config, 10, 5) == Ok(Nil)
}

pub fn poll_5s_http_5999ms_and_100ms_invalid_test() {
  let config_5999 = fixture_config(5999, 65_536)
  assert client.validate_poll_configuration(config_5999, 10, 5)
    == Error(
      "invalid_poll_config: http_timeout_ms_insufficient_for_poll_margin",
    )

  let config_100 = fixture_config(100, 65_536)
  assert client.validate_poll_configuration(config_100, 10, 5)
    == Error(
      "invalid_poll_config: http_timeout_ms_insufficient_for_poll_margin",
    )
}

pub fn negative_poll_timeout_invalid_test() {
  let config =
    client.default_configuration("http://nas-1.tail55d152.ts.net:1", "secret_token_never_leak")

  assert client.validate_poll_configuration(config, 10, -1)
    == Error("invalid_poll_config: poll_timeout_seconds_negative")
}

pub fn limit_zero_invalid_test() {
  let config =
    client.default_configuration("http://nas-1.tail55d152.ts.net:1", "secret_token_never_leak")

  assert client.validate_poll_configuration(config, 0, 5)
    == Error("invalid_poll_config: limit_below_min")
  assert client.validate_poll_configuration(config, -1, 5)
    == Error("invalid_poll_config: limit_below_min")
}

pub fn http_timeout_0_and_60001_invalid_test() {
  let config_zero = fixture_config(0, 65_536)
  assert client.validate_poll_configuration(config_zero, 10, 0)
    == Error("invalid_poll_config: timeout_ms_below_min")

  let config_over = fixture_config(60_001, 65_536)
  assert client.validate_poll_configuration(config_over, 10, 0)
    == Error("invalid_poll_config: timeout_ms_exceeds_max")
}

pub fn max_response_bytes_0_and_10485761_invalid_test() {
  let config_zero = fixture_config(10_000, 0)
  assert client.validate_poll_configuration(config_zero, 10, 5)
    == Error("invalid_poll_config: max_response_bytes_below_min")

  let config_over = fixture_config(10_000, 10_485_761)
  assert client.validate_poll_configuration(config_over, 10, 5)
    == Error("invalid_poll_config: max_response_bytes_exceeds_max")
}

pub fn poll_updates_invalid_config_precedes_network_test() {
  let default_cfg =
    client.default_configuration("http://nas-1.tail55d152.ts.net:1", "secret_token_never_leak")
  let neg_poll_res = client.poll_updates(default_cfg, -10, 10, -1)
  assert neg_poll_res
    == Error("invalid_poll_config: poll_timeout_seconds_negative")

  let short_http_cfg = fixture_config(100, 65_536)
  let margin_res = client.poll_updates(short_http_cfg, 0, 10, 5)
  assert margin_res
    == Error(
      "invalid_poll_config: http_timeout_ms_insufficient_for_poll_margin",
    )

  let zero_limit_res = client.poll_updates(default_cfg, 0, 0, 5)
  assert zero_limit_res == Error("invalid_poll_config: limit_below_min")

  case neg_poll_res {
    Error(msg) -> {
      assert !string.contains(msg, "secret_token_never_leak")
      assert !string.contains(msg, "http_poll_network_error")
    }
    Ok(_) -> panic as "expected validator error before network"
  }
}
