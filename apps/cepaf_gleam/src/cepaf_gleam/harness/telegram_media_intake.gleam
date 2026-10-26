//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_media_intake</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T2, SC-TELEGRAM-MEDIA-T3, SC-TELEGRAM-MEDIA-T4, SC-TELEGRAM-JOURNEY-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Media intake (wave 6h): the one place that chains the media stages for a
//// captioned media message the service accepted at ingress.
////
////   reference -> download (T2) -> inspect (T3) -> store put (T4) -> reply
////
//// Every stage keeps its own law; this module only orders them and turns the
//// result into the typed reply the journeys expect. The reply vocabulary is
//// the journey contract's (INV-TGJ-04): `backend_unavailable` when no media
//// policy or no transport is configured (nothing was fetched), `denied` when a
//// stage refused the content, `ok` only when the bytes were fetched, passed
//// inspection and are stored under their recomputed digest. No status is ever
//// invented from the declared fields alone.
////
//// Honest limits:
//// * The caption's directive is REPORTED in the reply, never executed by this
////   module: a captioned `/status` photo answers the media reply, and the
////   operator sees which directive the caption carried.
//// * Nothing here bounds wall time; the caller runs `run` inside its own
////   bounded observation window (download deadlines live in the transport,
////   the store write deadline is the caller's).
//// * `Accepted(sniffed)` from inspection narrows the container type; it never
////   means the content is safe to open. The reply says `sniffed`, not `type`.

import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_media_download as download
import cepaf_gleam/harness/telegram_media_inspect as inspect
import cepaf_gleam/harness/telegram_media_ref as media_ref
import cepaf_gleam/harness/telegram_media_store as store
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string

/// What a deployment binds for media: the store policy and, when it exists,
/// the transport that fetches bytes from Telegram. A missing transport is a
/// declared absence, answered as `backend_unavailable`.
pub type Binding {
  Binding(policy: store.Policy, transport: Option(download.Transport))
}

pub type Outcome {
  /// No media policy is bound to the service at all.
  NotConfigured
  /// A policy exists but no transport: nothing is fetched.
  TransportNotConfigured
  /// The download adapter refused or aborted; the label carries no payload.
  DownloadRefused(label: String)
  /// Fetched, but the sniffed container type is not allowed for the kind.
  InspectionRejected(reason: String, sniffed: inspect.Sniffed)
  /// Fetched and inspected, but the store refused the object.
  StoreRefused(reason: String)
  /// Fetched, inspected and present under its recomputed digest.
  Stored(
    sha256_hex: String,
    bytes: Int,
    sniffed: inspect.Sniffed,
    written: Bool,
    expires_at_ms: Int,
  )
  /// The store could not be measured before the ceiling check.
  UsageUnavailable(reason: String)
}

/// Run the chain for one reference. Pure apart from the injected transport and
/// the store under `binding.policy`; `token` is consulted only by the download
/// adapter and never appears in any outcome.
pub fn run(
  binding: Option(Binding),
  ref: media_ref.MediaRef,
  token: fn() -> Result(String, String),
  now_ms: Int,
) -> Outcome {
  case binding {
    None -> NotConfigured
    Some(Binding(policy: _, transport: None)) -> TransportNotConfigured
    Some(Binding(policy: policy, transport: Some(transport))) -> {
      let fetched = download.download(ref, [], token, transport)
      case inspect.inspect_fetched(fetched) {
        Error(label) -> DownloadRefused(label)
        Ok(inspect.Rejected(reason, sniffed)) ->
          InspectionRejected(reason, sniffed)
        Ok(inspect.Accepted(sniffed)) ->
          case fetched {
            download.Fetched(
              kind: kind,
              file_unique_id: unique,
              bytes: _,
              sha256_hex: claimed,
              content: content,
            ) ->
              case store.usage(policy) {
                Error(reason) -> UsageUnavailable(reason)
                Ok(usage) ->
                  case
                    store.put(
                      policy,
                      kind,
                      unique,
                      content,
                      claimed,
                      now_ms,
                      usage,
                    )
                  {
                    store.Written(stored) ->
                      Stored(
                        stored.sha256_hex,
                        stored.bytes,
                        sniffed,
                        True,
                        stored.expires_at_ms,
                      )
                    store.AlreadyStored(stored) ->
                      Stored(
                        stored.sha256_hex,
                        stored.bytes,
                        sniffed,
                        False,
                        stored.expires_at_ms,
                      )
                    store.Refused(reason) -> StoreRefused(reason)
                  }
              }
            // `inspect_fetched` only accepts a `Fetched` outcome, so this arm
            // is unreachable; it is kept total rather than asserted.
            _ -> DownloadRefused("download_not_fetched")
          }
      }
    }
  }
}

/// Journey status of an outcome (INV-TGJ-04 vocabulary).
pub fn status(outcome: Outcome) -> String {
  case outcome {
    NotConfigured | TransportNotConfigured | UsageUnavailable(_) ->
      "backend_unavailable"
    DownloadRefused(_) | InspectionRejected(_, _) | StoreRefused(_) -> "denied"
    Stored(_, _, _, _, _) -> "ok"
  }
}

/// The name the caption's directive classified to, for the reply only.
pub fn directive_label(dir: guard.ParsedDirective) -> String {
  case dir {
    guard.DirectReadTool(tool) -> tool
    guard.PreservedDirective(name, _) -> name
    guard.DeniedMutation(tool, _) -> tool
    guard.UnknownDirective(name) -> name
  }
}

/// The typed media reply. Declared fields are labelled `declared_*` and carry
/// the sender's words; observed fields appear only on `ok`.
pub fn reply_json(
  outcome: Outcome,
  ref: media_ref.MediaRef,
  caption_directive: String,
  request_id: String,
) -> String {
  let declared = [
    #("capability", json.string("media.intake")),
    #("status", json.string(status(outcome))),
    #("request_id", json.string(request_id)),
    #("caption_directive", json.string(caption_directive)),
    #("declared_kind", json.string(media_ref.kind_label(ref.kind))),
    #("declared_file_unique_id", json.string(ref.file_unique_id)),
    #("declared_size_bytes", json.nullable(ref.declared_size_bytes, json.int)),
    #("declared_mime", json.nullable(ref.declared_mime, json.string)),
    #("runtime_admission", json.string("NOT_GRANTED")),
  ]
  let specific = case outcome {
    NotConfigured -> [#("reason", json.string("media_not_configured"))]
    TransportNotConfigured -> [
      #("reason", json.string("media_transport_not_configured")),
    ]
    UsageUnavailable(reason) -> [
      #("reason", json.string("media_store_usage_unavailable:" <> reason)),
    ]
    DownloadRefused(label) -> [#("reason", json.string(label))]
    InspectionRejected(reason, sniffed) -> [
      #("reason", json.string(reason)),
      #("sniffed", json.string(sniffed_label(sniffed))),
    ]
    StoreRefused(reason) -> [
      #("reason", json.string("store_refused:" <> reason)),
    ]
    Stored(sha, bytes, sniffed, written, expires_at_ms) -> [
      #("sha256", json.string(sha)),
      #("bytes", json.int(bytes)),
      #("sniffed", json.string(sniffed_label(sniffed))),
      #("written", json.bool(written)),
      #("expires_at_ms", json.int(expires_at_ms)),
    ]
  }
  json.object(list_append(declared, specific)) |> json.to_string
}

/// Reply for a stored input row whose media field could not be decoded; the
/// row is refused, never guessed at.
pub fn refusal_reply(reason: String, request_id: String) -> String {
  json.object([
    #("capability", json.string("media.intake")),
    #("status", json.string("denied")),
    #("request_id", json.string(request_id)),
    #("reason", json.string(reason)),
    #("runtime_admission", json.string("NOT_GRANTED")),
  ])
  |> json.to_string
}

pub fn sniffed_label(sniffed: inspect.Sniffed) -> String {
  case sniffed {
    inspect.Jpeg -> "jpeg"
    inspect.Png -> "png"
    inspect.Gif -> "gif"
    inspect.Webp -> "webp"
    inspect.Ogg -> "ogg"
    inspect.Mp3 -> "mp3"
    inspect.Mp4 -> "mp4"
    inspect.Pdf -> "pdf"
    inspect.Zip -> "zip"
    inspect.Unknown -> "unknown"
  }
}

/// One-line human summary for logs; never contains the token or file ids.
pub fn summary(outcome: Outcome) -> String {
  case outcome {
    Stored(sha, bytes, sniffed, written, _) ->
      "stored "
      <> string.slice(sha, 0, 12)
      <> " bytes="
      <> int.to_string(bytes)
      <> " sniffed="
      <> sniffed_label(sniffed)
      <> case written {
        True -> " written"
        False -> " already_stored"
      }
    other -> status(other)
  }
}

fn list_append(a: List(x), b: List(x)) -> List(x) {
  case a {
    [] -> b
    [head, ..tail] -> [head, ..list_append(tail, b)]
  }
}
