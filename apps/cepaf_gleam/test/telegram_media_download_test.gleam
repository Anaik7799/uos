//// Media design T2: bounded download adapter with injected transport.
//// Every law is observed through closures that report their own invocation on a
//// Subject, so "never called" is an observation, not an assumption.

import cepaf_gleam/harness/telegram_media_download as dl
import cepaf_gleam/harness/telegram_media_ref as ref
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should

const secret = "FAKE-TOKEN-xyz"

fn mk_ref(
  kind: ref.MediaKind,
  uid: String,
  declared: Option(Int),
) -> ref.MediaRef {
  ref.MediaRef(
    kind: kind,
    file_unique_id: uid,
    file_id: "fid-" <> uid,
    declared_size_bytes: declared,
    declared_mime: None,
    declared_duration_s: None,
    caption: None,
  )
}

fn good_token() -> Result(String, String) {
  Ok(secret)
}

/// Drain and count every event currently queued on a subject.
fn drain(events: Subject(String)) -> List(String) {
  case process.receive(events, 0) {
    Ok(e) -> [e, ..drain(events)]
    Error(_) -> []
  }
}

fn count_prefix(events: List(String), prefix: String) -> Int {
  list.count(events, fn(e) { string.starts_with(e, prefix) })
}

/// A transport whose chunks come from a queue Subject: each reader call pops one
/// item, an empty queue is end of stream. Every effect reports itself.
fn queued_transport(
  events: Subject(String),
  meta: Result(dl.FileMeta, String),
  chunks: List(BitArray),
) -> dl.Transport {
  let queue = process.new_subject()
  list.each(chunks, fn(c) { process.send(queue, c) })
  dl.Transport(
    get_file: fn(fid, deadline) {
      process.send(
        events,
        "get_file:" <> fid <> ":" <> string.inspect(deadline),
      )
      meta
    },
    open_stream: fn(url, deadline, _cap) {
      process.send(events, "open:" <> url <> "|" <> string.inspect(deadline))
      Ok(fn() {
        process.send(events, "read")
        case process.receive(queue, 0) {
          Ok(c) -> Ok(Some(c))
          Error(_) -> Ok(None)
        }
      })
    },
  )
}

fn meta(path: String, size: Option(Int)) -> Result(dl.FileMeta, String) {
  Ok(dl.FileMeta(file_path: path, declared_size_bytes: size))
}

// ---------------------------------------------------------------- cap table

pub fn cap_for_table_is_exact_test() {
  dl.cap_for(ref.Photo) |> should.equal(10_485_760)
  dl.cap_for(ref.Voice) |> should.equal(5_242_880)
  dl.cap_for(ref.Audio) |> should.equal(26_214_400)
  dl.cap_for(ref.Document) |> should.equal(26_214_400)
  dl.cap_for(ref.Video) |> should.equal(52_428_800)
  dl.cap_for(ref.Sticker) |> should.equal(1_048_576)
  dl.cap_for(ref.Animation) |> should.equal(10_485_760)
  dl.cap_for(ref.Unsupported("poll")) |> should.equal(0)
}

pub fn deadlines_match_design_test() {
  dl.get_file_deadline_ms |> should.equal(3000)
  dl.stream_deadline_ms |> should.equal(15_000)
}

// ------------------------------------------------- rejection before any effect

pub fn unsupported_kind_never_calls_transport_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [<<1>>])
  let outcome =
    dl.download(mk_ref(ref.Unsupported("poll"), "u1", None), [], good_token, t)
  outcome |> should.equal(dl.Rejected(dl.UnsupportedKind("poll")))
  drain(events) |> should.equal([])
}

pub fn unsupported_kind_never_reads_token_test() {
  let probe = process.new_subject()
  let token = fn() {
    process.send(probe, "token")
    Ok(secret)
  }
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [])
  let _ = dl.download(mk_ref(ref.Unsupported("poll"), "u1", None), [], token, t)
  process.receive(probe, 0) |> should.be_error
}

pub fn already_fetched_never_calls_transport_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [<<1>>])
  dl.download(
    mk_ref(ref.Photo, "u-dup", None),
    ["other", "u-dup"],
    good_token,
    t,
  )
  |> should.equal(dl.Rejected(dl.AlreadyFetched("u-dup")))
  drain(events) |> should.equal([])
}

pub fn identity_is_file_unique_id_not_file_id_test() {
  // already_fetched holds the file_id of the unit: that must NOT dedup it.
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [<<1>>])
  let outcome =
    dl.download(mk_ref(ref.Photo, "u9", None), ["fid-u9"], good_token, t)
  case outcome {
    dl.Fetched(..) -> Nil
    other -> {
      should.equal(other, dl.Aborted(0, 0))
      Nil
    }
  }
}

pub fn declared_over_cap_in_ref_never_calls_transport_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [<<1>>])
  dl.download(mk_ref(ref.Voice, "u2", Some(5_242_881)), [], good_token, t)
  |> should.equal(dl.Rejected(dl.DeclaredOverCap(5_242_881, 5_242_880)))
  drain(events) |> should.equal([])
}

pub fn declared_exactly_at_cap_is_not_rejected_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [<<1>>])
  let outcome =
    dl.download(mk_ref(ref.Sticker, "u3", Some(1_048_576)), [], good_token, t)
  case outcome {
    dl.Fetched(bytes: 1, ..) -> Nil
    other -> {
      should.equal(other, dl.Aborted(0, 0))
      Nil
    }
  }
}

pub fn declared_over_cap_in_filemeta_never_opens_stream_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", Some(1_048_577)), [<<1>>])
  dl.download(mk_ref(ref.Sticker, "u4", None), [], good_token, t)
  |> should.equal(dl.Rejected(dl.DeclaredOverCap(1_048_577, 1_048_576)))
  let seen = drain(events)
  count_prefix(seen, "get_file:fid-u4:3000") |> should.equal(1)
  count_prefix(seen, "open:") |> should.equal(0)
  count_prefix(seen, "read") |> should.equal(0)
}

pub fn declared_over_cap_in_filemeta_never_reads_token_test() {
  let probe = process.new_subject()
  let token = fn() {
    process.send(probe, "token")
    Ok(secret)
  }
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", Some(2_000_000)), [])
  let _ = dl.download(mk_ref(ref.Sticker, "u4b", None), [], token, t)
  process.receive(probe, 0) |> should.be_error
}

// ------------------------------------------------------------ stream bounds

pub fn missing_declared_size_proceeds_and_is_bounded_by_stream_cap_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [<<1, 2, 3>>])
  case dl.download(mk_ref(ref.Sticker, "u5", None), [], good_token, t) {
    dl.Fetched(bytes: 3, ..) -> Nil
    other -> {
      should.equal(other, dl.Aborted(0, 0))
      Nil
    }
  }
  // and the same absent declaration cannot exceed the cap on the stream
  let events2 = process.new_subject()
  let big = bit_array.from_string(string.repeat("a", 600_000))
  let t2 = queued_transport(events2, meta("a/b.bin", None), [big, big])
  dl.download(mk_ref(ref.Sticker, "u5b", None), [], good_token, t2)
  |> should.equal(dl.Aborted(1_200_000, 1_048_576))
}

pub fn stream_over_cap_aborts_and_reader_not_called_again_test() {
  let events = process.new_subject()
  let chunk = bit_array.from_string(string.repeat("x", 600_000))
  // five chunks queued; the second pushes the total over the sticker cap
  let t =
    queued_transport(events, meta("a/b.bin", None), [
      chunk,
      chunk,
      chunk,
      chunk,
      chunk,
    ])
  let outcome = dl.download(mk_ref(ref.Sticker, "u6", None), [], good_token, t)
  outcome |> should.equal(dl.Aborted(1_200_000, 1_048_576))
  case outcome {
    dl.Aborted(observed, cap) -> { observed > cap } |> should.be_true
    _ -> should.fail()
  }
  count_prefix(drain(events), "read") |> should.equal(2)
}

pub fn stream_exactly_at_cap_is_fetched_test() {
  let events = process.new_subject()
  let body = bit_array.from_string(string.repeat("y", 1_048_576))
  let t = queued_transport(events, meta("a/b.bin", None), [body])
  case dl.download(mk_ref(ref.Sticker, "u6b", None), [], good_token, t) {
    dl.Fetched(bytes: 1_048_576, ..) -> Nil
    other -> {
      should.equal(other, dl.Aborted(0, 0))
      Nil
    }
  }
}

pub fn declared_small_but_stream_large_is_aborted_test() {
  // the declared size is attacker controlled: it must not relax the stream cap
  let events = process.new_subject()
  let body = bit_array.from_string(string.repeat("z", 1_048_577))
  let t = queued_transport(events, meta("a/b.bin", Some(10)), [body])
  dl.download(mk_ref(ref.Sticker, "u6c", Some(10)), [], good_token, t)
  |> should.equal(dl.Aborted(1_048_577, 1_048_576))
}

pub fn chunk_bound_rejects_endless_stream_test() {
  let events = process.new_subject()
  let t =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) {
        Ok(fn() {
          process.send(events, "read")
          Ok(Some(<<1>>))
        })
      },
    )
  dl.download(mk_ref(ref.Photo, "u7", None), [], good_token, t)
  |> should.equal(dl.Rejected(dl.StreamReadFailed("chunk_bound")))
  count_prefix(drain(events), "read") |> should.equal(4096)
}

pub fn chunk_bound_counts_empty_chunks_test() {
  let events = process.new_subject()
  let t =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) {
        Ok(fn() {
          process.send(events, "read")
          Ok(Some(<<>>))
        })
      },
    )
  dl.download(mk_ref(ref.Photo, "u7b", None), [], good_token, t)
  |> should.equal(dl.Rejected(dl.StreamReadFailed("chunk_bound")))
  count_prefix(drain(events), "read") |> should.equal(4096)
}

// ------------------------------------------------------------ success path

pub fn fetched_carries_bytes_and_sha256_of_hello_test() {
  let events = process.new_subject()
  let t =
    queued_transport(events, meta("photos/file_1.jpg", Some(5)), [
      <<"he":utf8>>,
      <<"llo":utf8>>,
    ])
  dl.download(mk_ref(ref.Photo, "u8", Some(5)), [], good_token, t)
  |> should.equal(
    dl.Fetched(
      kind: ref.Photo,
      file_unique_id: "u8",
      bytes: 5,
      sha256_hex: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
      content: <<"hello":utf8>>,
    ),
  )
}

pub fn empty_stream_is_fetched_with_empty_digest_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [])
  dl.download(mk_ref(ref.Document, "u8b", None), [], good_token, t)
  |> should.equal(
    dl.Fetched(
      kind: ref.Document,
      file_unique_id: "u8b",
      bytes: 0,
      sha256_hex: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      content: <<>>,
    ),
  )
}

pub fn url_is_built_exactly_and_deadlines_passed_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("photos/file_1.jpg", None), [])
  let _ = dl.download(mk_ref(ref.Photo, "u9", None), [], good_token, t)
  let seen = drain(events)
  seen
  |> list.contains(
    "open:https://api.telegram.org/file/botFAKE-TOKEN-xyz/photos/file_1.jpg|15000",
  )
  |> should.be_true
  seen |> list.contains("get_file:fid-u9:3000") |> should.be_true
}

// --------------------------------------------------------- failure mapping

pub fn token_unavailable_is_rejected_before_stream_open_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", None), [<<1>>])
  dl.download(
    mk_ref(ref.Photo, "u10", None),
    [],
    fn() { Error("token_store_down") },
    t,
  )
  |> should.equal(dl.Rejected(dl.TokenUnavailable("token_store_down")))
  count_prefix(drain(events), "open:") |> should.equal(0)
}

pub fn get_file_failure_is_typed_test() {
  let events = process.new_subject()
  let t = queued_transport(events, Error("timeout"), [<<1>>])
  dl.download(mk_ref(ref.Photo, "u11", None), [], good_token, t)
  |> should.equal(dl.Rejected(dl.GetFileFailed("timeout")))
  count_prefix(drain(events), "open:") |> should.equal(0)
}

pub fn invalid_file_paths_are_refused_before_token_or_stream_test() {
  list.each(["", "/abs/x", "a/../b", "a?x=1", "a#f"], fn(path) {
    let probe = process.new_subject()
    let token = fn() {
      process.send(probe, "token")
      Ok(secret)
    }
    let events = process.new_subject()
    let t = queued_transport(events, meta(path, None), [<<1>>])
    dl.download(mk_ref(ref.Photo, "u12", None), [], token, t)
    |> should.equal(dl.Rejected(dl.GetFileFailed("invalid_file_path")))
    process.receive(probe, 0) |> should.be_error
    count_prefix(drain(events), "open:") |> should.equal(0)
  })
}

pub fn stream_open_and_read_failures_are_typed_test() {
  let t_open =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) { Error("refused") },
    )
  dl.download(mk_ref(ref.Photo, "u13", None), [], good_token, t_open)
  |> should.equal(dl.Rejected(dl.StreamOpenFailed("refused")))
  let t_read =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) { Ok(fn() { Error("reset") }) },
    )
  dl.download(mk_ref(ref.Photo, "u13b", None), [], good_token, t_read)
  |> should.equal(dl.Rejected(dl.StreamReadFailed("reset")))
}

// ------------------------------------------------------------ token secrecy

fn leak_free(value: a) -> Nil {
  let text = string.inspect(value)
  string.contains(text, secret) |> should.be_false
  case string.split(text, "/file/bot") {
    [] -> Nil
    [_, ..tails] ->
      list.each(tails, fn(tail) {
        string.starts_with(tail, "[REDACTED]") |> should.be_true
      })
  }
}

fn url_in_error() -> String {
  "failed GET https://api.telegram.org/file/botFAKE-TOKEN-xyz/photos/f.jpg end"
}

pub fn no_outcome_leaks_the_token_on_any_path_test() {
  let events = process.new_subject()
  let ok_t =
    queued_transport(events, meta("photos/f.jpg", Some(3)), [<<1, 2, 3>>])
  // success
  leak_free(dl.download(mk_ref(ref.Photo, "s1", Some(3)), [], good_token, ok_t))
  // unsupported / duplicate / declared over cap
  leak_free(dl.download(
    mk_ref(ref.Unsupported("x"), "s2", None),
    [],
    good_token,
    ok_t,
  ))
  leak_free(dl.download(mk_ref(ref.Photo, "s3", None), ["s3"], good_token, ok_t))
  leak_free(dl.download(
    mk_ref(ref.Sticker, "s4", Some(99_999_999)),
    [],
    good_token,
    ok_t,
  ))
  // get_file error that itself carries the URL
  let t_gf = queued_transport(events, Error(url_in_error()), [])
  leak_free(dl.download(mk_ref(ref.Photo, "s5", None), [], good_token, t_gf))
  // token error carrying a URL
  leak_free(dl.download(
    mk_ref(ref.Photo, "s6", None),
    [],
    fn() { Error(url_in_error()) },
    ok_t,
  ))
  // open_stream error carrying the URL and, separately, the bare token
  let t_open_url =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) { Error(url_in_error()) },
    )
  leak_free(dl.download(
    mk_ref(ref.Photo, "s7", None),
    [],
    good_token,
    t_open_url,
  ))
  let t_open_bare =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) { Error("auth rejected for " <> secret) },
    )
  leak_free(dl.download(
    mk_ref(ref.Photo, "s8", None),
    [],
    good_token,
    t_open_bare,
  ))
  // reader error carrying the URL and, separately, the bare token
  let t_read_url =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) { Ok(fn() { Error(url_in_error()) }) },
    )
  leak_free(dl.download(
    mk_ref(ref.Photo, "s9", None),
    [],
    good_token,
    t_read_url,
  ))
  let t_read_bare =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) {
        Ok(fn() { Error("connection to " <> secret <> " reset") })
      },
    )
  leak_free(dl.download(
    mk_ref(ref.Photo, "s10", None),
    [],
    good_token,
    t_read_bare,
  ))
  // aborted and chunk-bound
  let big = bit_array.from_string(string.repeat("a", 1_048_577))
  let t_big = queued_transport(events, meta("a/b.bin", None), [big])
  leak_free(dl.download(mk_ref(ref.Sticker, "s11", None), [], good_token, t_big))
}

pub fn transport_error_url_is_redacted_in_the_returned_reason_test() {
  let events = process.new_subject()
  let t = queued_transport(events, Error(url_in_error()), [])
  dl.download(mk_ref(ref.Photo, "r1", None), [], good_token, t)
  |> should.equal(
    dl.Rejected(dl.GetFileFailed(
      "failed GET https://api.telegram.org/file/bot[REDACTED]/photos/f.jpg end",
    )),
  )
}

pub fn bare_token_in_stream_error_is_scrubbed_test() {
  let t =
    dl.Transport(
      get_file: fn(_, _) { meta("a/b.bin", None) },
      open_stream: fn(_, _, _) { Error("bad " <> secret) },
    )
  dl.download(mk_ref(ref.Photo, "r2", None), [], good_token, t)
  |> should.equal(dl.Rejected(dl.StreamOpenFailed("bad [REDACTED]")))
}

// ------------------------------------------------------------ redact_file_url

pub fn redact_without_marker_is_unchanged_test() {
  dl.redact_file_url("") |> should.equal("")
  dl.redact_file_url("plain text, /file/ and bot")
  |> should.equal("plain text, /file/ and bot")
}

pub fn redact_replaces_up_to_next_slash_test() {
  dl.redact_file_url("x https://h/file/bot123:ABC/photos/a.jpg y")
  |> should.equal("x https://h/file/bot[REDACTED]/photos/a.jpg y")
}

pub fn redact_to_end_of_string_without_slash_test() {
  dl.redact_file_url("tail /file/bot123:ABC")
  |> should.equal("tail /file/bot[REDACTED]")
  dl.redact_file_url("/file/bot") |> should.equal("/file/bot[REDACTED]")
}

pub fn redact_two_markers_both_redacted_test() {
  let out = dl.redact_file_url("a /file/botAAA/x b /file/botBBB/y c")
  out |> should.equal("a /file/bot[REDACTED]/x b /file/bot[REDACTED]/y c")
  string.contains(out, "AAA") |> should.be_false
  string.contains(out, "BBB") |> should.be_false
}

pub fn redact_is_idempotent_test() {
  list.each(
    [
      "",
      "no marker",
      "a /file/botAAA/x b /file/botBBB/y c",
      "/file/bot",
      "/file/bot/file/botZ",
      "end /file/botQQQ",
      "/file/bot[REDACTED]/p",
    ],
    fn(s) {
      let once = dl.redact_file_url(s)
      dl.redact_file_url(once) |> should.equal(once)
    },
  )
}

// ----------------------------------------- review M2-01 / M2-08: size integrity

pub fn received_bytes_differing_from_getfile_size_are_not_stored_test() {
  // fewer bytes than getFile declared: a truncated body
  let events = process.new_subject()
  let short =
    queued_transport(events, meta("a/b.bin", Some(5)), [<<1, 2, 3>>])
  dl.download(mk_ref(ref.Photo, "z1", None), [], good_token, short)
  |> should.equal(dl.Rejected(dl.StreamReadFailed("size_mismatch")))
  // more bytes than declared
  let long =
    queued_transport(events, meta("a/b.bin", Some(3)), [<<1, 2>>, <<3, 4, 5>>])
  dl.download(mk_ref(ref.Photo, "z2", None), [], good_token, long)
  |> should.equal(dl.Rejected(dl.StreamReadFailed("size_mismatch")))
}

pub fn received_bytes_equal_to_the_getfile_size_are_fetched_test() {
  let events = process.new_subject()
  let t = queued_transport(events, meta("a/b.bin", Some(3)), [<<1, 2>>, <<3>>])
  let assert dl.Fetched(bytes: 3, content: <<1, 2, 3>>, ..) =
    dl.download(mk_ref(ref.Photo, "z4", None), [], good_token, t)
}

fn failing_reader_transport(reason: String) -> dl.Transport {
  dl.Transport(
    get_file: fn(_, _) { meta("a/b.bin", None) },
    open_stream: fn(_, _, _) { Ok(fn() { Error(reason) }) },
  )
}

pub fn an_advertised_total_over_the_kind_cap_is_the_over_cap_abort_test() {
  // photo cap 10_485_760; the transport reports the 20_000_000 total at once
  dl.download(
    mk_ref(ref.Photo, "z5", None),
    [],
    good_token,
    failing_reader_transport("range_total_over_limit:20000000"),
  )
  |> should.equal(dl.Aborted(20_000_000, 10_485_760))
}

pub fn an_over_limit_reason_within_the_cap_stays_a_read_failure_test() {
  dl.download(
    mk_ref(ref.Photo, "z6", None),
    [],
    good_token,
    failing_reader_transport("range_total_over_limit:5"),
  )
  |> should.equal(
    dl.Rejected(dl.StreamReadFailed("range_total_over_limit:5")),
  )
  dl.download(
    mk_ref(ref.Photo, "z7", None),
    [],
    good_token,
    failing_reader_transport("range_total_over_limit:abc"),
  )
  |> should.equal(
    dl.Rejected(dl.StreamReadFailed("range_total_over_limit:abc")),
  )
}
