import gleam/bit_array
import gleam/regexp
import gleam/result

pub type PreflightError {
  NonUtf8Content
  SensitiveContent(rule: String)
}

/// Fail closed on high-confidence credential material before any snapshot or
/// digest operation. This deliberately detects only bounded, reviewable
/// signatures; it is one gate in addition to source allowlisting and review,
/// not a claim of complete secret detection.
pub fn preflight_text(bytes: BitArray) -> Result(Nil, PreflightError) {
  use text <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error(NonUtf8Content),
  )

  case
    matches(text, "-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    matches(
      text,
      "(?i)(?:client_secret|api_key|access_token|refresh_token|password)[[:space:]]*[=:][[:space:]]*[A-Za-z0-9_./+=-]{16,}",
    ),
    matches(
      text,
      "(?:^|[^A-Za-z0-9])(?:AKIA[A-Z0-9]{16}|ghp_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9_-]{20,})",
    )
  {
    True, _, _ -> Error(SensitiveContent("private_key_pem"))
    _, True, _ -> Error(SensitiveContent("credential_assignment"))
    _, _, True -> Error(SensitiveContent("credential_token"))
    False, False, False -> Ok(Nil)
  }
}

fn matches(text: String, pattern: String) -> Bool {
  let assert Ok(compiled) = regexp.from_string(pattern)
  regexp.check(with: compiled, content: text)
}
