//// Closed EV86 document/media surface. This serves historical recorded previews;
//// it does not implement studio synthesis, authenticate music, or grant admission.
//// File observations assume a cooperative responsive filesystem. They refuse
//// observed symlinks/changes, but are not a descriptor-relative hostile-race VFS.
//// In the HTTP integration, paths have already passed through Mist's URI parser.
//// This module does not establish original wire-target bounds or lexical identity.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/charlist.{type Charlist}
import gleam/http.{type Method, Get, Head}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/uri

pub const document_limit = 2_097_152

pub const media_limit = 4_194_304

pub const path_limit = 4096

const player = "docs/music/20260907-1052-swarm-durga-player.md"

const studio = "docs/music/20260907-1145-cybernetic-raga-durga-and-22-shruti-studio.md"

const yaman = "generated/20260907-1100-uos-hive-sings-yaman-teentaal.wav"

const mix = "generated/20260907-1230-uos-hive-sings-full-mix.wav"

const base = "http://nas-1.tail55d152.ts.net:4100"

pub opaque type Root {
  Root(path: String, public_base: String)
}

pub type Failure {
  MissingRoot
  InvalidPath
  MissingFile
  UnsafeFile
  ByteLimit
  ChangedFile(stage: String)
  InvalidMedia
}

pub type Resource {
  Player
  Studio
  Enhanced
  Baseline
  Yaman
  Mix
}

type Mode {
  Read
  Binary
  Raw
}

type Info {
  Info(
    size: Int,
    kind: String,
    mode: Int,
    inode: Int,
    device: Int,
    modified: Dynamic,
    changed: Dynamic,
  )
}

@external(erlang, "os", "getenv")
fn getenv(name: Charlist, default: Charlist) -> Charlist

@external(erlang, "file", "read_link_info")
fn link_info(path: String) -> Result(Dynamic, Dynamic)

@external(erlang, "file", "read_file_info")
fn descriptor_info(fd: Dynamic) -> Result(Dynamic, Dynamic)

@external(erlang, "file", "open")
fn open_file(path: String, modes: List(Mode)) -> Result(Dynamic, Dynamic)

@external(erlang, "file", "read")
fn read_file(fd: Dynamic, count: Int) -> Dynamic

@external(erlang, "file", "close")
fn close_file(fd: Dynamic) -> Dynamic

pub fn root(path: String) -> Result(Root, Failure) {
  case
    string.byte_size(path) > 1
    && string.byte_size(path) <= 1024
    && string.starts_with(path, "/")
    && !string.ends_with(path, "/")
    && safe_parts(string.drop_start(path, 1))
  {
    True -> Ok(Root(path, base))
    False -> Error(MissingRoot)
  }
}

pub fn configured_root() -> Result(Root, Failure) {
  let path =
    getenv(charlist.from_string("UOS_MUSIC_ROOT"), charlist.from_string(""))
    |> charlist.to_string
  let origin =
    getenv(
      charlist.from_string("UOS_MUSIC_PUBLIC_BASE"),
      charlist.from_string(base),
    )
    |> charlist.to_string
  root_with_public_base(path, origin)
}

/// The operator must configure the actual same-origin Tailnet listener. Request
/// Host headers never select media origins. This validates syntax, not ownership.
pub fn root_with_public_base(
  path: String,
  origin: String,
) -> Result(Root, Failure) {
  use selected <- result.try(root(path))
  case public_base_valid(origin) {
    True -> Ok(Root(..selected, public_base: origin))
    False -> Error(MissingRoot)
  }
}

pub fn public_base_valid(origin: String) -> Bool {
  case string.byte_size(origin) <= 128, string.split(origin, "://") {
    True, [scheme, authority] if scheme == "http" || scheme == "https" -> {
      let #(host, port_ok) = case string.split(authority, ":") {
        [host] -> #(host, True)
        [host, port] -> #(host, case int.parse(port) {
          Ok(n) -> n >= 1 && n <= 65_535 && int.to_string(n) == port
          Error(_) -> False
        })
        _ -> #("", False)
      }
      let suffix = ".tail55d152.ts.net"
      let node = string.drop_end(host, string.length(suffix))
      port_ok
      && string.ends_with(host, suffix)
      && string.byte_size(node) >= 1
      && string.byte_size(node) <= 63
      && !string.starts_with(node, "-")
      && !string.ends_with(node, "-")
      && list.all(string.to_utf_codepoints(node), fn(c) {
        let n = string.utf_codepoint_to_int(c)
        n >= 97 && n <= 122 || n >= 48 && n <= 57 || n == 45
      })
    }
    _, _ -> False
  }
}

fn safe_parts(path: String) -> Bool {
  let parts = string.split(path, "/")
  list.length(parts) <= 32
  && list.all(parts, fn(part) {
    part != ""
    && part != "."
    && part != ".."
    && list.all(string.to_utf_codepoints(part), fn(c) {
      let n = string.utf_codepoint_to_int(c)
      n >= 32 && n < 127 && n != 37 && n != 92 && n != 63 && n != 35
    })
  })
}

fn music_namespace(path: String) -> Bool {
  let path = path |> string.lowercase |> string.replace("\\", "/")
  string.starts_with(path, "/docs/music")
  || string.starts_with(path, "/files/docs/music")
  || string.starts_with(path, "/raw/docs/music")
  || string.starts_with(path, "/media/music")
}

/// Inspect the supplied application path before generic application routing.
/// Mist supplies an already-parsed request.path. Original wire-target protection
/// remains unestablished. Reserve encoded/normalised music paths at this layer.
pub fn handles(path: String) -> Bool {
  case string.byte_size(path) > path_limit {
    // Application-path refusal. Mist has already parsed the wire request target.
    True -> True
    False -> {
      let decoded = namespace_decode(path)
      music_namespace(path)
      || music_namespace(decoded)
      || music_namespace("/" <> string.join(uri.path_segments(path), "/"))
      || music_namespace("/" <> string.join(uri.path_segments(decoded), "/"))
    }
  }
}

// Decode valid escapes for namespace reservation even when another escape is
// malformed. Resolution still uses exact original bytes and refuses all aliases.
fn namespace_decode(path: String) -> String {
  case string.split(path, "%") {
    [first, ..rest] ->
      first
      <> string.join(
        list.map(rest, fn(part) {
          let prefix = "%" <> string.slice(part, 0, 2)
          uri.percent_decode(prefix) |> result.unwrap(prefix)
          <> string.drop_start(part, 2)
        }),
        "",
      )
    [] -> path
  }
}

pub fn resolve(path: String) -> Result(Resource, Failure) {
  case path {
    "/docs/music/player"
    | "/files/docs/music/player"
    | "/docs/music/20260907-1052-swarm-durga-player.md"
    | "/files/docs/music/20260907-1052-swarm-durga-player.md" -> Ok(Player)
    "/docs/music/studio"
    | "/files/docs/music/studio"
    | "/docs/music/20260907-1145-cybernetic-raga-durga-and-22-shruti-studio.md"
    | "/files/docs/music/20260907-1145-cybernetic-raga-durga-and-22-shruti-studio.md" ->
      Ok(Studio)
    "/media/music/historical-enhanced.mp3" -> Ok(Enhanced)
    "/media/music/historical-baseline.mp3" -> Ok(Baseline)
    "/media/music/historical-yaman.wav" -> Ok(Yaman)
    "/media/music/historical-mix.wav" -> Ok(Mix)
    _ -> Error(InvalidPath)
  }
}

fn info(value: Dynamic) -> Result(Info, Failure) {
  let decoder = {
    use size <- decode.field(1, decode.int)
    use kind <- decode.field(2, atom.decoder())
    use modified <- decode.field(5, decode.dynamic)
    use changed <- decode.field(6, decode.dynamic)
    use mode <- decode.field(7, decode.int)
    use device <- decode.field(9, decode.int)
    use inode <- decode.field(11, decode.int)
    decode.success(Info(
      size,
      atom.to_string(kind),
      mode,
      inode,
      device,
      modified,
      changed,
    ))
  }
  decode.run(value, decoder) |> result.map_error(fn(_) { UnsafeFile })
}

fn stat(path: String) -> Result(Info, Failure) {
  link_info(path) |> result.map_error(fn(_) { MissingFile }) |> result.try(info)
}

fn directories(
  parts: List(String),
  current: String,
  seen: List(#(String, Info)),
) -> Result(List(#(String, Info)), Failure) {
  case parts {
    [] -> Ok(seen)
    [part, ..rest] -> {
      let path = current <> "/" <> part
      use observed <- result.try(stat(path))
      case
        observed.kind == "directory"
        && int.bitwise_and(observed.mode, 0o111) != 0
      {
        True -> directories(rest, path, [#(path, observed), ..seen])
        False -> Error(UnsafeFile)
      }
    }
  }
}

fn unchanged(entries: List(#(String, Info))) -> Bool {
  list.all(entries, fn(entry) {
    let #(path, before) = entry
    stat(path) == Ok(before)
  })
}

fn bounded_read(
  root: Root,
  relative: String,
  limit: Int,
) -> Result(BitArray, Failure) {
  // Only fixed internal catalog entries reach this function.
  let full = root.path <> "/" <> relative
  let parts = string.split(string.drop_start(full, 1), "/")
  use parent_info <- result.try(
    directories(list.take(parts, list.length(parts) - 1), "", []),
  )
  use before <- result.try(stat(full))
  case before.kind != "regular" || int.bitwise_and(before.mode, 0o444) == 0 {
    True -> Error(UnsafeFile)
    False ->
      case before.size <= 0 || before.size > limit {
        True -> Error(ByteLimit)
        False -> {
          use fd <- result.try(
            open_file(full, [Read, Binary, Raw])
            |> result.map_error(fn(_) { UnsafeFile }),
          )
          let opened =
            descriptor_info(fd)
            |> result.map_error(fn(_) { UnsafeFile })
            |> result.try(info)
          let outcome = case opened == Ok(before) {
            False -> Error(ChangedFile("open identity"))
            True -> {
              let value = read_file(fd, limit + 1)
              let decoder = {
                use tag <- decode.field(0, atom.decoder())
                use bits <- decode.field(1, decode.bit_array)
                decode.success(#(atom.to_string(tag), bits))
              }
              case decode.run(value, decoder) {
                Ok(#("ok", bits)) ->
                  case bit_array.byte_size(bits) == before.size {
                    True -> Ok(bits)
                    False -> Error(ChangedFile("read length"))
                  }
                _ -> Error(UnsafeFile)
              }
            }
          }
          let after =
            descriptor_info(fd)
            |> result.map_error(fn(_) { UnsafeFile })
            |> result.try(info)
          let closed =
            close_file(fd)
            |> decode.run(atom.decoder())
            |> result.map(atom.to_string)
          case
            after == Ok(before)
            && closed == Ok("ok")
            && stat(full) == Ok(before)
            && unchanged(parent_info)
          {
            True -> outcome
            False -> Error(ChangedFile("final identity"))
          }
        }
      }
  }
}

pub fn validate_mp3(bits: BitArray) -> Result(BitArray, Failure) {
  // Bounded ID3v2 header and following MPEG frame signature, not an MP3 decoder.
  let bytes = bit_array.byte_size(bits)
  case bits {
    <<"ID3", version:8, 0:8, 0:8, a:8, b:8, c:8, d:8, _:bytes>>
      if bytes >= 128
      && bytes <= media_limit
      && version >= 3
      && version <= 4
      && a < 128
      && b < 128
      && c < 128
      && d < 128
    -> {
      let offset = 10 + a * 2_097_152 + b * 16_384 + c * 128 + d
      case bit_array.slice(bits, offset, 4) {
        Ok(<<255:8, sync:8, rate:8, _:8>>) -> {
          let version_bits =
            int.bitwise_and(int.bitwise_shift_right(sync, 3), 3)
          let layer = int.bitwise_and(int.bitwise_shift_right(sync, 1), 3)
          let bitrate = int.bitwise_shift_right(rate, 4)
          let sample = int.bitwise_and(int.bitwise_shift_right(rate, 2), 3)
          case
            sync >= 224
            && version_bits != 1
            && layer != 0
            && bitrate > 0
            && bitrate < 15
            && sample != 3
            && bytes >= offset + 128
          {
            True -> Ok(bits)
            False -> Error(InvalidMedia)
          }
        }
        _ -> Error(InvalidMedia)
      }
    }
    _ -> Error(InvalidMedia)
  }
}

pub fn validate_wav(bits: BitArray) -> Result(BitArray, Failure) {
  let bytes = bit_array.byte_size(bits)
  case bits {
    <<
      "RIFF",
      size:32-little,
      "WAVEfmt ",
      16:32-little,
      1:16-little,
      1:16-little,
      rate:32-little,
      byte_rate:32-little,
      2:16-little,
      16:16-little,
      "data",
      data_size:32-little,
      samples:bytes,
    >>
      if rate >= 8000
      && rate <= 96_000
      && byte_rate == rate * 2
      && data_size > 0
      && data_size % 2 == 0
      && size + 8 == bytes
      && bytes <= media_limit
    ->
      case bit_array.byte_size(samples) == data_size {
        True -> Ok(bits)
        False -> Error(InvalidMedia)
      }
    _ -> Error(InvalidMedia)
  }
}

fn previews(bits: BitArray) -> Result(#(BitArray, BitArray), Failure) {
  use text <- result.try(
    bit_array.to_string(bits) |> result.map_error(fn(_) { InvalidMedia }),
  )
  case string.split(text, "data:audio/mp3;base64,") {
    [_, first, second] -> {
      use a <- result.try(preview(first))
      use b <- result.try(preview(second))
      Ok(#(a, b))
    }
    _ -> Error(InvalidMedia)
  }
}

fn preview(tail: String) -> Result(BitArray, Failure) {
  use encoded <- result.try(
    string.split_once(tail, "\"") |> result.map_error(fn(_) { InvalidMedia }),
  )
  let #(encoded, _) = encoded
  use bits <- result.try(
    bit_array.base64_decode(encoded) |> result.map_error(fn(_) { InvalidMedia }),
  )
  validate_mp3(bits)
}

fn escape(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}

fn document(which: Resource, original: String, public_base: String) -> String {
  let title = case which {
    Studio -> "22-Shruti studio: recorded previews"
    _ -> "Historical music previews"
  }
  let page = case which {
    Studio -> "/docs/music/studio"
    _ -> "/docs/music/player"
  }
  "<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>"
  <> title
  <> "</title></head><body><header><a href='"
  <> base
  <> "/'>UOS</a> · <a href='"
  <> base
  <> "/docs/music/player'>Player</a> · <a href='"
  <> base
  <> "/docs/music/studio'>Studio</a></header>"
  <> navigation(public_base, page)
  <> "<main id='rendered'><h1>"
  <> title
  <> "</h1><p>Historical recorded previews from the preserved player document. Interactive synthesis is not available on this page.</p>"
  <> "<nav aria-label='Document view'><a href='"
  <> public_base
  <> page
  <> "#rendered'>Rendered preview</a> · <a href='"
  <> public_base
  <> page
  <> "#raw-source'>Raw source</a></nav>"
  <> "<section><h2>Historical enhanced recording</h2><audio controls preload='none'><source src='"
  <> public_base
  <> "/media/music/historical-enhanced.mp3' type='audio/mpeg'></audio></section>"
  <> "<section><h2>Historical baseline recording</h2><audio controls preload='none'><source src='"
  <> public_base
  <> "/media/music/historical-baseline.mp3' type='audio/mpeg'></audio></section>"
  <> "<details id='raw-source'><summary>Raw source: preserved document (historical claims)</summary><pre>"
  <> escape(original)
  <> "</pre></details>"
  <> checklist()
  <> "<nav aria-label='Previous and next'><a rel='prev' href='"
  <> public_base
  <> "/docs/music/player'>Previous: Player</a> · <a rel='next' href='"
  <> public_base
  <> "/docs/music/studio'>Next: Studio</a></nav>"
  <> "</main><footer><a href='"
  <> base
  <> "/planning'>Planning</a> · Recorded previews; no musical authenticity or quality claim.</footer></body></html>"
}

fn navigation(public_base: String, page: String) -> String {
  "<aside><nav aria-label='Grouped navigation'><section><h2>Command &amp; Control</h2><a href='"
  <> base
  <> "/'>Cockpit</a> · <a href='"
  <> base
  <> "/planning'>Planning</a></section><section><h2>Knowledge Base</h2><a href='"
  <> base
  <> "/wiki'>Wiki</a> · <a href='"
  <> base
  <> "/zk'>Zettelkasten</a></section><section><h2>Repository &amp; Governance</h2><a href='"
  <> base
  <> "/files/AGENTS.md'>Policy</a> · <a href='"
  <> public_base
  <> "/docs/music/player'>Music documents</a></section></nav></aside>"
  <> "<section aria-label='Status bar'><p>Recorded previews only · live synthesis unverified · no admission change</p><a href='"
  <> public_base
  <> page
  <> "'>"
  <> public_base
  <> page
  <> "</a><p>URL text can be selected manually; automatic copy is unavailable.</p></section>"
  <> "<nav aria-label='Breadcrumb'><a href='"
  <> base
  <> "/'>UOS</a> / <a href='"
  <> public_base
  <> "/docs/music/player'>Music</a> / Recorded preview</nav>"
}

fn checklist() -> String {
  let groups = [
    #("Metadata and navigation", [
      "01 Timestamp: historical source retained",
      "02 Navigation: full Tailnet links provided",
      "03 Fractal trace: bounded document surface",
      "04 Evidence: source view provided",
    ]),
    #("Purity and storage", [
      "05 Purity: no page script required",
      "06 Native interfaces: no new NIF",
      "07 Storage: read-only route; hardware interlock untested",
    ]),
    #("Testing and mathematical gates", [
      "08 C1-C8: full acceptance pending",
      "09 Mathematics: musical proof pending",
      "10 Runtime modalities: unverified",
      "11 Regression: candidate evidence required",
    ]),
    #("Cross-language control", [
      "12 Gleam: typed document and media response",
      "13 Hermes: native evidence outside this page",
      "14 ZigVM: not exercised",
      "15 MAX: not exercised",
      "16 Telemetry: live correlation unverified",
    ]),
    #("Governance and Jujutsu", [
      "17 Sovereign review: no admission granted",
      "18 Jujutsu: source revision requires separate evidence",
    ]),
  ]
  "<details><summary>18-point verification checklist — no runtime or admission claim</summary>"
  <> string.join(
    list.map(groups, fn(group) {
      let #(name, items) = group
      "<details><summary>"
      <> name
      <> "</summary><ul>"
      <> string.join(
        list.map(items, fn(item) { "<li>" <> item <> "</li>" }),
        "",
      )
      <> "</ul></details>"
    }),
    "",
  )
  <> "<details><summary>Domain 6: Provenance</summary><p>EV94–109 remain NOT_ADMITTED. Historical source claims are preserved as evidence, not current runtime or admission authority. This page does not demonstrate live synthesis or musical authenticity. The configured origin is syntax-validated, not authenticated.</p></details></details>"
}

pub fn content(
  root: Root,
  resource: Resource,
) -> Result(#(String, BitArray), Failure) {
  case resource {
    Player | Studio -> {
      let path = case resource {
        Player -> player
        _ -> studio
      }
      use original <- result.try(bounded_read(root, path, document_limit))
      use source <- result.try(
        bit_array.to_string(original)
        |> result.map_error(fn(_) { InvalidMedia }),
      )
      use data <- result.try(case resource {
        Player -> Ok(original)
        _ -> bounded_read(root, player, document_limit)
      })
      use _ <- result.try(previews(data))
      Ok(#(
        "text/html; charset=utf-8",
        bit_array.from_string(document(resource, source, root.public_base)),
      ))
    }
    Enhanced | Baseline -> {
      use data <- result.try(bounded_read(root, player, document_limit))
      use pair <- result.try(previews(data))
      let #(a, b) = pair
      Ok(
        #("audio/mpeg", case resource {
          Enhanced -> a
          _ -> b
        }),
      )
    }
    Yaman | Mix -> {
      let path = case resource {
        Yaman -> yaman
        _ -> mix
      }
      use bits <- result.try(bounded_read(root, path, media_limit))
      use bits <- result.try(validate_wav(bits))
      Ok(#("audio/wav", bits))
    }
  }
}

fn reply(
  status: Int,
  mime: String,
  bits: BitArray,
  method: Method,
) -> Response(BitArray) {
  response.new(status)
  |> response.set_header("content-type", mime)
  |> response.set_header(
    "content-length",
    int.to_string(bit_array.byte_size(bits)),
  )
  |> response.set_header("x-content-type-options", "nosniff")
  |> response.set_header("cache-control", "no-store")
  |> response.set_header(
    "content-security-policy",
    "default-src 'none'; media-src 'self'; frame-ancestors 'none'; base-uri 'none'",
  )
  |> response.set_body(case method {
    Head -> <<>>
    _ -> bits
  })
}

pub fn handle(
  config: Result(Root, Failure),
  method: Method,
  path: String,
) -> Response(BitArray) {
  case string.byte_size(path) > path_limit {
    True ->
      reply(
        414,
        "text/plain; charset=utf-8",
        <<"Request path exceeds 4096 bytes">>,
        method,
      )
    False ->
      case resolve(path), method {
        Error(_), _ ->
          reply(
            404,
            "text/plain; charset=utf-8",
            <<"Music resource not found">>,
            method,
          )
        Ok(_), Get | Ok(_), Head -> {
          let output = {
            use root <- result.try(config)
            use resource <- result.try(resolve(path))
            content(root, resource)
          }
          case output {
            Ok(#(mime, bits)) -> reply(200, mime, bits, method)
            Error(MissingRoot) ->
              reply(
                503,
                "text/plain; charset=utf-8",
                <<"Music content root is not configured">>,
                method,
              )
            Error(_) ->
              reply(
                404,
                "text/plain; charset=utf-8",
                <<"Music resource unavailable">>,
                method,
              )
          }
        }
        Ok(_), _ ->
          reply(
            405,
            "text/plain; charset=utf-8",
            <<"Method not allowed">>,
            method,
          )
          |> response.set_header("allow", "GET, HEAD")
      }
  }
}
