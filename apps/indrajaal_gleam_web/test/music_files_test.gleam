import document_render_contract_test as legacy
import gleam/bit_array
import gleam/erlang/charlist.{type Charlist}
import gleam/http.{Get, Head, Post}
import gleam/http/response
import gleam/io
import gleam/list
import gleam/string
import gleeunit/should
import indrajaal/music_files as music

fn check(name: String, run: fn() -> Nil) {
  run()
  io.println("PASS " <> name)
}

fn configured() {
  music.configured_root()
}

@external(erlang, "os", "getenv")
fn getenv(name: Charlist, default: Charlist) -> Charlist

fn fixture(name: String) {
  let path =
    getenv(charlist.from_string("UOS_MUSIC_ROOT"), charlist.from_string(""))
    |> charlist.to_string
  music.root(path <> "/cases/" <> name)
}

pub fn aliases_test() {
  music.resolve("/docs/music/player") |> should.equal(Ok(music.Player))
  music.resolve("/files/docs/music/player") |> should.equal(Ok(music.Player))
  music.resolve("/docs/music/20260907-1052-swarm-durga-player.md")
  |> should.equal(Ok(music.Player))
  music.resolve("/files/docs/music/studio") |> should.equal(Ok(music.Studio))
  music.resolve(
    "/docs/music/20260907-1145-cybernetic-raga-durga-and-22-shruti-studio.md",
  )
  |> should.equal(Ok(music.Studio))
}

pub fn malformed_paths_test() {
  list.each(
    [
      "/docs/music/missing",
      "/docs/music/../secret",
      "/docs/music/%2e%2e/secret",
      "/docs/%6dusic/player",
      "/docs/music/player%00",
      "/docs/music/player\u{0000}",
      "/docs/music\\player",
      "/docs\\music\\player",
      "/DOCS/MUSIC/player",
      "/docs/music//player",
      "/docs/other/../music/player",
      "/files/docs/music/../../AGENTS.md",
      "/raw/docs/music/player",
      "/media/music/no.wav",
    ],
    fn(path) {
      music.handles(path) |> should.be_true
      let r = music.handle(configured(), Get, path)
      r.status |> should.equal(404)
      bit_array.to_string(r.body)
      |> should.equal(Ok("Music resource not found"))
    },
  )
  music.handles("/health") |> should.be_false
  music.handles("/docs/design/plan.md") |> should.be_false
}

pub fn configuration_and_method_test() {
  list.each(
    ["", "/", "/tmp/../bad", "relative", "/tmp/link/", "/tmp/bad%20"],
    fn(p) { music.root(p) |> should.equal(Error(music.MissingRoot)) },
  )
  music.handle(Error(music.MissingRoot), Get, "/docs/music/player").status
  |> should.equal(503)
  music.handle(configured(), Post, "/docs/music/player").status
  |> should.equal(405)
}

pub fn semantic_documents_test() {
  let assert Ok(selected) = configured()
  let assert Ok(_) = music.content(selected, music.Player)
    as "EV86_PLAYER_CONTENT"
  list.each(
    ["/docs/music/player", "/docs/music/studio", "/files/docs/music/player"],
    fn(path) {
      let r = music.handle(configured(), Get, path)
      r.status |> should.equal(200)
      let assert Ok(body) = bit_array.to_string(r.body)
      string.contains(body, "<audio controls preload='none'>") |> should.be_true
      string.contains(body, "<script") |> should.be_false
      string.contains(body, "autoplay") |> should.be_false
      string.contains(body, "Historical") |> should.be_true
      response.get_header(r, "content-security-policy")
      |> should.equal(Ok(
        "default-src 'none'; media-src 'self'; frame-ancestors 'none'; base-uri 'none'",
      ))
    },
  )
}

pub fn mp3_response_test() {
  list.each(
    [
      "/media/music/historical-enhanced.mp3",
      "/media/music/historical-baseline.mp3",
    ],
    fn(path) {
      let r = music.handle(configured(), Get, path)
      r.status |> should.equal(200)
      response.get_header(r, "content-type") |> should.equal(Ok("audio/mpeg"))
      response.get_header(r, "content-length") |> should.equal(Ok("480696"))
      bit_array.byte_size(r.body) |> should.equal(480_696)
      music.validate_mp3(r.body) |> should.equal(Ok(r.body))
    },
  )
}

pub fn wav_response_test() {
  let r = music.handle(configured(), Get, "/media/music/historical-mix.wav")
  r.status |> should.equal(200)
  response.get_header(r, "content-type") |> should.equal(Ok("audio/wav"))
  response.get_header(r, "content-length") |> should.equal(Ok("2646044"))
  music.validate_wav(r.body) |> should.equal(Ok(r.body))
}

pub fn head_response_test() {
  let r =
    music.handle(configured(), Head, "/media/music/historical-enhanced.mp3")
  r.status |> should.equal(200)
  r.body |> should.equal(<<>>)
  response.get_header(r, "content-length") |> should.equal(Ok("480696"))
}

pub fn wrong_magic_test() {
  music.validate_mp3(<<"not mp3">>) |> should.equal(Error(music.InvalidMedia))
  music.validate_mp3(<<"ID3">>) |> should.equal(Error(music.InvalidMedia))
  music.validate_mp3(bit_array.from_string("ID3" <> string.repeat("x", 200)))
  |> should.equal(Error(music.InvalidMedia))
  music.validate_wav(<<"RIFFbogusWAVE">>)
  |> should.equal(Error(music.InvalidMedia))
}

pub fn filesystem_refusals_test() {
  list.each(
    [
      "missing",
      "symlink-file",
      "symlink-parent",
      "root-symlink",
      "directory",
      "fifo",
      "denied",
      "zero-file",
      "oversize-document",
    ],
    fn(name) {
      let r = music.handle(fixture(name), Get, "/docs/music/player")
      r.status |> should.equal(404)
      r.body |> should.equal(<<"Music resource unavailable">>)
    },
  )
}

pub fn document_payload_refusals_test() {
  list.each(
    ["invalid-base64", "wrong-magic", "duplicate-preview", "single-preview"],
    fn(name) {
      music.handle(fixture(name), Get, "/docs/music/player").status
      |> should.equal(404)
    },
  )
  music.handle(fixture("missing-studio"), Get, "/docs/music/studio").status
  |> should.equal(404)
}

pub fn exact_document_bound_test() {
  music.handle(fixture("exact-document"), Get, "/docs/music/player").status
  |> should.equal(200)
}

pub fn wav_bounds_and_size_test() {
  let r =
    music.handle(fixture("exact-wav"), Get, "/media/music/historical-mix.wav")
  r.status |> should.equal(200)
  response.get_header(r, "content-length") |> should.equal(Ok("4194304"))
  list.each(["oversize-wav", "bad-wav-size"], fn(name) {
    music.handle(fixture(name), Get, "/media/music/historical-mix.wav").status
    |> should.equal(404)
  })
}

pub fn main() {
  check("aliases", aliases_test)
  check("malformed_paths", malformed_paths_test)
  check("configuration_and_method", configuration_and_method_test)
  check("semantic_documents", semantic_documents_test)
  check("mp3_response", mp3_response_test)
  check("wav_response", wav_response_test)
  check("head_response", head_response_test)
  check("wrong_magic", wrong_magic_test)
  check("filesystem_refusals", filesystem_refusals_test)
  check("document_payload_refusals", document_payload_refusals_test)
  check("exact_document_bound", exact_document_bound_test)
  check("wav_bounds_and_size", wav_bounds_and_size_test)
  check(
    "legacy_parser_escape",
    legacy.document_client_parser_has_escaped_newline_test,
  )
  check(
    "legacy_inert_source",
    legacy.document_source_is_inert_before_rendering_test,
  )
  check(
    "legacy_collapsed_checklist",
    legacy.document_checklist_starts_collapsed_test,
  )
}
