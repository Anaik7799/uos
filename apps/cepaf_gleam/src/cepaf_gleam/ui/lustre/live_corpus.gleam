//// INV-FRESH-4100-01: stateless disk projection, no content or metadata cache.

import cepaf_gleam/ui/lustre/knowledge_explorer
import cepaf_gleam/ui/lustre/shell
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import gleam/uri
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import simplifile

pub const base_url = "http://nas-1.tail55d152.ts.net:4100"

pub const wiki_index = "docs/wiki/20260905-1801-uos-zk-km-corpus-index.md"

pub const zk_index = "docs/zk/20260905-1801-moc-uos-unified-master.md"

pub const system_prompt = "docs/sop/20261031-1012-uos-canonical-fractal-system-prompt.md"

pub const canonical_artifacts = [
  "docs/sop/20261031-1012-uos-canonical-fractal-system-prompt.md",
  "docs/wiki/20261031-1012-uos-otp29-json-anti-brittle-mcp-and-fractal-symbiosis-wiki.md",
  "docs/zk/20261031-1012-adr-otp29-json-total-quarantine-and-canonical-mcp-seams.md",
  "governance/capability-inventory/20261031-1012-mcp-anti-brittle-fractal-km-index.json",
]

pub const triad_manifest = "governance/capability-inventory/wiki-zk-km.toml"

pub const brain_roots = [
  "docs/zk",
  "docs/wiki",
  "docs/sop",
  "docs/handover",
  "docs/design",
  "docs/journal",
  "docs/architecture",
  "contracts/rules",
  "governance/capability-inventory",
  "governance/agents",
  "governance/planning",
  "formal/lean",
  "formal/quint",
]

const trees = [
  "docs",
  "contracts",
  "governance/capability-inventory",
  "governance/agents",
  "governance/planning",
  "governance/sources",
  "formal/lean",
  "formal/quint",
  ".agents/skills",
  ".claude/rules",
  ".claude/skills",
  "plugins",
]

const seeds = ["AGENTS.md", "CLAUDE.md", "GEMINI.md", "README.md"]

const extensions = [
  ".md",
  ".toml",
  ".json",
  ".lean",
  ".qnt",
  ".allium",
  ".txt",
  ".mli",
  ".ml",
  ".gleam",
  ".zig",
  ".sql",
  ".sh",
  ".html",
  ".svg",
]

const markers = [
  ".env",
  ".pem",
  ".key",
  ".p12",
  ".pfx",
  "id_rsa",
  "id_ed25519",
  "credentials",
  "secret_key",
  ".sqlite",
  ".db",
  "-wal",
  "-shm",
]

@external(erlang, "cepaf_gleam_ffi", "get_env")
fn env(name: String) -> Result(String, Nil)

@external(erlang, "live_corpus_ffi", "read")
fn descriptor_read(root: String, path: String, cap: Int) -> Result(String, Int)

@external(erlang, "live_corpus_ffi", "names")
fn names(path: String) -> List(String)

@external(erlang, "live_corpus_ffi", "sha256")
pub fn sha256(content: String) -> String

pub type Entry {
  Entry(path: String, bytes: Int, mtime: Int, directory: Bool)
}

pub fn workspace_root() -> String {
  case
    result.unwrap(env("UOS_MCP_WORKSPACE_ROOT"), ""),
    result.unwrap(env("PROJECT_ROOT"), "")
  {
    "", "" -> "/home/an/NAS-setup/uos"
    "", root -> root
    root, _ -> root
  }
}

pub fn split_target(target: String) -> #(String, Option(String)) {
  case string.split_once(target, "?") {
    Ok(#(p, q)) -> #(p, Some(q))
    Error(_) -> #(target, None)
  }
}

fn safe_segment(s: String) -> Bool {
  s != ""
  && s != "."
  && s != ".."
  && !list.any(["/", "\\", "%"], fn(c) { string.contains(s, c) })
  && {
    case bit_array.to_string(bit_array.from_string(s)) {
      Ok(_) -> True
      Error(_) -> False
    }
  }
  && list.all(string.to_utf_codepoints(s), fn(c) {
    let n = string.utf_codepoint_to_int(c)
    n >= 32 && n != 127
  })
}

pub fn decode_path(path: String) -> Result(String, Int) {
  let parts = string.split(path, "/") |> list.filter(fn(p) { p != "" })
  use decoded <- result.try(
    list.try_map(parts, fn(p) {
      use d <- result.try(
        uri.percent_decode(p) |> result.map_error(fn(_) { 400 }),
      )
      case safe_segment(d) {
        True -> Ok(d)
        False -> Error(403)
      }
    }),
  )
  Ok(string.join(decoded, "/"))
}

fn clean_relative(path: String) -> Bool {
  let lowered = string.lowercase(path)
  !string.starts_with(path, "/")
  && list.all(string.split(path, "/"), safe_segment)
  && !list.any(markers, fn(m) { string.contains(lowered, m) })
}

fn within(path: String, root: String) -> Bool {
  path == root || string.starts_with(path, root <> "/")
}

pub fn allowed_directory(path: String) -> Bool {
  path == ""
  || {
    clean_relative(path)
    && list.any(trees, fn(t) {
      within(path, t) || string.starts_with(t, path <> "/")
    })
  }
}

pub fn allowed_file(path: String) -> Bool {
  clean_relative(path)
  && {
    list.contains(seeds, path)
    || {
      list.any(trees, fn(t) { string.starts_with(path, t <> "/") })
      && list.any(extensions, fn(e) {
        string.ends_with(string.lowercase(path), e)
      })
      && {
        !string.starts_with(path, "plugins/")
        || string.contains(path, "/references/")
        || string.ends_with(path, ".md")
        || string.ends_with(path, ".json")
      }
    }
  }
}

pub fn brain_file(path: String) -> Bool {
  allowed_file(path)
  && {
    list.contains(["AGENTS.md", "CLAUDE.md", "GEMINI.md"], path)
    || string.starts_with(path, ".agents/skills/")
    || list.any(brain_roots, fn(r) { string.starts_with(path, r <> "/") })
  }
  && list.any([".md", ".toml", ".json", ".lean", ".qnt"], fn(e) {
    string.ends_with(path, e)
  })
}

fn prefix_stat(
  root: String,
  parts: List(String),
) -> Result(simplifile.FileInfo, Int) {
  case parts {
    [] -> simplifile.link_info(root) |> result.map_error(fn(_) { 404 })
    [p, ..rest] -> {
      let next = root <> "/" <> p
      use info <- result.try(
        simplifile.link_info(next) |> result.map_error(fn(_) { 404 }),
      )
      case simplifile.file_info_type(info) {
        simplifile.Symlink -> Error(403)
        simplifile.Directory ->
          case rest {
            [] -> Ok(info)
            _ -> prefix_stat(next, rest)
          }
        simplifile.File ->
          case rest {
            [] ->
              case info.nlinks > 1 {
                True -> Error(403)
                False -> Ok(info)
              }
            _ -> Error(403)
          }
        _ -> Error(403)
      }
    }
  }
}

pub fn stat(root: String, path: String) -> Result(Entry, Int) {
  use _ <- result.try(case allowed_file(path) || allowed_directory(path) {
    True -> Ok(Nil)
    False -> Error(403)
  })
  use info <- result.try(
    prefix_stat(root, case path {
      "" -> []
      _ -> string.split(path, "/")
    }),
  )
  let directory = simplifile.file_info_type(info) == simplifile.Directory
  case
    { directory && allowed_directory(path) || !directory && allowed_file(path) }
  {
    True -> Ok(Entry(path, info.size, info.mtime_seconds, directory))
    False -> Error(403)
  }
}

pub fn read(root: String, path: String, cap: Int) -> Result(String, Int) {
  use _ <- result.try(case allowed_file(path) {
    True -> Ok(Nil)
    False -> Error(403)
  })
  use before <- result.try(stat(root, path))
  use _ <- result.try(case before.directory {
    True -> Error(403)
    False ->
      case before.bytes > cap {
        True -> Error(413)
        False -> Ok(Nil)
      }
  })
  use content <- result.try(descriptor_read(root, path, cap))
  use _ <- result.try(stat(root, path))
  Ok(content)
}

pub fn children(root: String, path: String) -> List(Entry) {
  case stat(root, path) {
    Ok(entry) if entry.directory ->
      names(root <> "/" <> path)
      |> list.filter(safe_segment)
      |> list.filter_map(fn(n) {
        stat(root, case path {
          "" -> n
          _ -> path <> "/" <> n
        })
      })
      |> list.sort(newest)
    _ -> []
  }
}

fn newest(x: Entry, y: Entry) -> order.Order {
  case int.compare(y.mtime, x.mtime) {
    order.Eq -> string.compare(y.path, x.path)
    other -> other
  }
}

/// Bounded depth and entry count; stat-only, never hashes the corpus.
pub fn catalog(root: String) -> List(Entry) {
  let paths = list.append(seeds, trees)
  catalog_paths(root, paths)
}

/// Brain Memory inspects only its thirteen roots and the canonical local skill.
/// Every call observes disk metadata afresh; no catalog is retained.
pub fn brain_catalog(root: String) -> List(Entry) {
  catalog_paths(root, list.flatten([
    seeds,
    [".agents/skills/uos-km-triad-brain-memory/SKILL.md"],
    brain_roots,
  ]))
  |> list.filter(fn(e) { brain_file(e.path) })
}

fn catalog_paths(root: String, paths: List(String)) -> List(Entry) {
  let #(rev_entries, _) = list.fold(paths, #([], 20_000), fn(state, p) {
    walk(root, p, 0, state)
  })
  rev_entries
  |> list.reverse
  |> list.sort(newest)
}

fn walk(
  root: String,
  path: String,
  depth: Int,
  state: #(List(Entry), Int),
) -> #(List(Entry), Int) {
  let #(rev_entries, remaining) = state
  case remaining <= 0 || depth > 16 {
    True -> state
    False ->
      case stat(root, path) {
        Error(_) -> state
        Ok(e) if !e.directory -> #([e, ..rev_entries], remaining - 1)
        Ok(_) ->
          list.fold(children(root, path), state, fn(acc, child) {
            let #(rev_acc, remaining) = acc
            case remaining <= 0 || depth >= 16 {
              True -> acc
              False -> case child.directory {
                False -> #([child, ..rev_acc], remaining - 1)
                True -> walk(root, child.path, depth + 1, acc)
              }
            }
          })
      }
  }
}

pub fn count(root: String, path: String) -> Int {
  let #(_, remaining) = walk(root, path, 0, #([], 20_000))
  20_000 - remaining
}

pub fn canonical_intact(root: String) -> Bool {
  list.all(["AGENTS.md", wiki_index, zk_index, triad_manifest], fn(p) {
    case stat(root, p) {
      Ok(e) -> !e.directory
      Error(_) -> False
    }
  })
}

pub fn freshness(res: response.Response(String)) -> response.Response(String) {
  res
  |> response.set_header(
    "cache-control",
    "no-store, no-cache, must-revalidate, max-age=0",
  )
  |> response.set_header("pragma", "no-cache")
  |> response.set_header("expires", "0")
  |> response.set_header("x-uos-freshness", "live-disk")
}

fn page(
  status: Int,
  title: String,
  path: String,
  body: Element(Nil),
) -> response.Response(String) {
  response.new(status)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(shell.render_page(title, path, body))
  |> freshness
}

fn failure(code: Int, path: String) -> response.Response(String) {
  page(
    code,
    case code {
      403 -> "Corpus Access Forbidden"
      413 -> "Corpus File Too Large"
      400 -> "Invalid Corpus Target"
      _ -> "Corpus File Missing"
    },
    path,
    h.div([], [
      h.h1([], [h.text("Live corpus request failed: " <> int.to_string(code))]),
      h.p([], [h.text(path)]),
      link("/km", "KM Index"),
    ]),
  )
}

fn link(url: String, label: String) -> Element(Nil) {
  h.a([a.href(url)], [h.text(label)])
}

pub fn file_url(path: String) -> String {
  "/files/" <> encode_path(path)
}

fn encode_path(path: String) -> String {
  string.split(path, "/") |> list.map(uri.percent_encode) |> string.join("/")
}

fn entry_links(e: Entry) -> Element(Nil) {
  h.tr([], [
    h.td([], [link(file_url(e.path), e.path)]),
    h.td([], [link(file_url(e.path) <> "?raw=1", "Raw")]),
    h.td([], [h.text(int.to_string(e.bytes))]),
    h.td([], [h.text(int.to_string(e.mtime))]),
  ])
}

fn parameter(query: Option(String), key: String) -> String {
  option_query(query)
  |> string.split("&")
  |> list.find_map(fn(pair) {
    case string.split_once(pair, "=") {
      Ok(#(k, v)) if k == key -> uri.percent_decode(string.replace(v, "+", " "))
      Error(_) -> Error(Nil)
      _ -> Error(Nil)
    }
  })
  |> result.unwrap("")
}

fn option_query(q: Option(String)) -> String {
  case q {
    Some(s) -> s
    None -> ""
  }
}

fn number(
  query: Option(String),
  key: String,
  default: Int,
  maximum: Int,
) -> Int {
  parameter(query, key)
  |> int.parse
  |> result.unwrap(default)
  |> int.clamp(0, maximum)
}

fn listing(
  root: String,
  rel: String,
  path: String,
  query: Option(String),
  title: String,
  explorer: Bool,
) -> response.Response(String) {
  let entries = children(root, rel)
  let pinned =
    list.filter(entries, fn(e) { e.path == wiki_index || e.path == zk_index })
  let sorted =
    list.append(
      pinned,
      list.filter(entries, fn(e) { e.path != wiki_index && e.path != zk_index }),
    )
  let offset = number(query, "offset", 0, 1_000_000)
  let shown = sorted |> list.drop(offset) |> list.take(200)
  page(
    200,
    title,
    path,
    h.div([], [
      h.h1([], [h.text(title)]),
      h.p([], [
        h.text(
          "LIVE DISK READ • CACHE-CONTROL: NO-STORE • "
          <> int.to_string(list.length(entries))
          <> " live files/directories",
        ),
      ]),
      case explorer {
        True ->
          knowledge_explorer.view(knowledge_explorer.init())
          |> element.map(fn(_) { Nil })
        False -> h.text("")
      },
      h.table([], list.map(shown, entry_links)),
      h.ul(
        [],
        list.map(shown, fn(e) {
          h.li([], [
            link(
              case rel {
                "docs/wiki" -> "/wiki/" <> uri.percent_encode(basename(e.path))
                "docs/zk" -> "/zk/" <> uri.percent_encode(basename(e.path))
                _ -> file_url(e.path)
              },
              e.path,
            ),
          ])
        }),
      ),
      case list.length(entries) > offset + 200 {
        True ->
          h.p([], [
            h.text("truncated • "),
            link(path <> "?offset=" <> int.to_string(offset + 200), "Next page"),
          ])
        False -> h.text("")
      },
      link("/km", "Up to Index"),
    ]),
  )
}

fn basename(path: String) -> String {
  string.split(path, "/") |> list.last |> result.unwrap(path)
}

pub fn slug_matches(path: String, raw: String) -> Bool {
  let matches = slug_matcher(normalize_token(raw))
  matches(path)
}

fn normalize_token(raw: String) -> String {
  raw
    |> string.split("|")
    |> list.first
    |> result.unwrap(raw)
    |> string.replace("[[wiki:", "")
    |> string.replace("[[zk:", "")
    |> string.replace("]]", "")
    |> string.lowercase
}

fn slug_matcher(token: String) -> fn(String) -> Bool {
  case string.starts_with(token, "adr-") {
    True -> {
      let middle = "-" <> token <> "-"
      let ending = "-" <> token <> ".md"
      let markdown = token <> ".md"
      fn(path) {
        let name = string.lowercase(basename(path))
        string.contains(name, middle)
        || string.ends_with(name, ending)
        || name == markdown
      }
    }
    False -> fn(path) {
      token != "" && string.contains(string.lowercase(basename(path)), token)
    }
  }
}

pub fn resolve(entries: List(Entry), target: String) -> List(Entry) {
  let markdown = target <> ".md"
  let suffix = "/" <> target
  let markdown_suffix = suffix <> ".md"
  let exact =
    list.filter(entries, fn(e) {
      e.path == target
      || e.path == markdown
      || string.ends_with(e.path, suffix)
      || string.ends_with(e.path, markdown_suffix)
    })
  case exact {
    [] -> {
      let matches = slug_matcher(normalize_token(target))
      list.filter(entries, fn(e) { matches(e.path) })
    }
    _ -> exact
  }
}

fn slug_page(
  root: String,
  rel: String,
  target: String,
  path: String,
  query: Option(String),
) -> response.Response(String) {
  // Check exact paths first so forbidden symlinks/hardlinks cannot become 404s.
  case stat(root, rel <> "/" <> target) {
    Error(403) -> failure(403, path)
    _ ->
      case
        resolve(
          children(root, rel)
            |> list.filter(fn(e) {
              string.ends_with(e.path, ".md") && !e.directory
            }),
          target,
        )
      {
        [] -> failure(404, path)
        [e] -> document(root, e.path, path, query)
        many ->
          page(
            300,
            "Disambiguate Wiki Slug",
            path,
            h.div([], [
              h.h1([], [h.text("Disambiguate Wiki Slug")]),
              h.ul(
                [],
                list.map(many, fn(e) {
                  h.li([], [
                    link(
                      case rel {
                        "docs/wiki" -> "/wiki/"
                        _ -> "/zk/"
                      }
                        <> uri.percent_encode(basename(e.path)),
                      e.path,
                    ),
                  ])
                }),
              ),
            ]),
          )
      }
  }
}

fn safe_href(href: String) -> Bool {
  string.starts_with(href, "https://")
  || string.starts_with(href, "http://")
  || string.starts_with(href, "/")
}

fn inline(text: String, budget: Int) -> List(Element(Nil)) {
  case budget <= 0 {
    True -> [h.text(text)]
    False ->
      case string.split_once(text, "[") {
        Error(_) -> [h.text(text)]
        Ok(#(before, rest)) ->
          case string.split_once(rest, "]") {
            Error(_) -> [h.text(text)]
            Ok(#(label, tail)) ->
              case
                string.starts_with(rest, "[") && string.starts_with(tail, "]")
              {
                True -> {
                  let tag = string.drop_start(label, 1)
                  let parts = string.split(tag, "|")
                  let target = list.first(parts) |> result.unwrap(tag)
                  let caption =
                    list.first(list.drop(parts, 1)) |> result.unwrap(target)
                  let route = case string.split_once(target, ":") {
                    Ok(#("wiki", t)) -> Some(#("/wiki/", t))
                    Ok(#("zk", t)) -> Some(#("/zk/", t))
                    _ -> None
                  }
                  list.append(
                    [
                      h.text(before),
                      case route {
                        Some(#(r, t)) ->
                          link(
                            r <> uri.percent_encode(t),
                            case string.starts_with(caption, "@") {
                              True -> t
                              False -> caption
                            },
                          )
                        None -> h.text("[[" <> tag <> "]]")
                      },
                    ],
                    inline(string.drop_start(tail, 1), budget - 1),
                  )
                }
                False ->
                  case string.starts_with(tail, "(") {
                    True ->
                      case string.split_once(string.drop_start(tail, 1), ")") {
                        Ok(#(href, after)) ->
                          list.append(
                            [
                              h.text(before),
                              case safe_href(href) {
                                True -> link(href, label)
                                False ->
                                  h.text("[" <> label <> "](" <> href <> ")")
                              },
                            ],
                            inline(after, budget - 1),
                          )
                        Error(_) -> [h.text(text)]
                      }
                    False ->
                      list.append(
                        [h.text(before <> "[" <> label <> "]")],
                        inline(tail, budget - 1),
                      )
                  }
              }
          }
      }
  }
}

fn markdown(content: String) -> Element(Nil) {
  h.div(
    [a.class("live-document")],
    string.split(content, "\n")
      |> list.map(fn(line) {
        case line {
          "# " <> t -> h.h1([], inline(t, 80))
          "## " <> t -> h.h2([], inline(t, 80))
          "### " <> t -> h.h3([], inline(t, 80))
          _ -> h.p([a.style("white-space", "pre-wrap")], inline(line, 80))
        }
      }),
  )
}

fn document(
  root: String,
  rel: String,
  path: String,
  query: Option(String),
) -> response.Response(String) {
  case read(root, rel, 4_194_304) {
    Error(code) -> failure(code, path)
    Ok(content) -> {
      let digest = sha256(content)
      let res = case parameter(query, "raw") == "1" {
        True ->
          response.new(200)
          |> response.set_body(content)
          |> response.set_header("content-type", "text/plain; charset=utf-8")
          |> response.set_header("content-security-policy", "sandbox")
          |> response.set_header("x-content-type-options", "nosniff")
          |> freshness
        False -> {
          let parent =
            string.split(rel, "/")
            |> list.reverse
            |> list.drop(1)
            |> list.reverse
            |> string.join("/")
          let siblings =
            children(root, parent) |> list.filter(fn(e) { !e.directory })
          let pos =
            list.index_fold(siblings, 0, fn(n, e, i) {
              case e.path == rel {
                True -> i
                False -> n
              }
            })
          let previous = case pos > 0 {
            True -> list.first(list.drop(siblings, pos - 1))
            False -> Error(Nil)
          }
          let next = list.first(list.drop(siblings, pos + 1))
          page(
            200,
            basename(rel),
            path,
            h.div([], [
              h.div([a.class("provenance")], [
                link(base_url <> file_url(rel), base_url <> file_url(rel)),
                h.p([], [h.text("Breadcrumbs: " <> rel)]),
                h.p([], [h.text("LIVE DISK READ • CACHE-CONTROL: NO-STORE")]),
                h.p([], [
                  h.text(
                    "SHA-256 "
                    <> digest
                    <> " • "
                    <> int.to_string(string.byte_size(content))
                    <> " bytes",
                  ),
                ]),
                link(file_url(rel), "Rendered"),
                h.text(" / "),
                link(file_url(rel) <> "?raw=1", "Raw"),
              ]),
              markdown(content),
              h.nav([], [
                case previous {
                  Ok(e) -> link(file_url(e.path), "Previous")
                  _ -> h.text("Previous")
                },
                h.text(" • "),
                link(file_url(parent), "Up to Index"),
                h.text(" • "),
                case next {
                  Ok(e) -> link(file_url(e.path), "Next")
                  _ -> h.text("Next")
                },
              ]),
            ]),
          )
        }
      }
      res |> response.set_header("x-uos-content-sha256", digest)
    }
  }
}

fn path_page(
  root: String,
  rel: String,
  path: String,
  query: Option(String),
) -> response.Response(String) {
  case stat(root, rel) {
    Ok(e) if e.directory ->
      listing(root, rel, path, query, "Live Directory — " <> rel, False)
    Ok(_) -> document(root, rel, path, query)
    Error(code) -> failure(code, path)
  }
}

fn docs_page(
  root: String,
  sub: String,
  path: String,
  query: Option(String),
) -> response.Response(String) {
  let primary = "docs/" <> sub
  case stat(root, primary) {
    Ok(_) -> path_page(root, primary, path, query)
    Error(403) -> failure(403, path)
    _ ->
      case stat(root, primary <> ".md") {
        Ok(_) -> document(root, primary <> ".md", path, query)
        _ ->
          case allowed_file(sub) || allowed_directory(sub) {
            True -> path_page(root, sub, path, query)
            False -> failure(404, path)
          }
      }
  }
}

fn hub(root: String) -> response.Response(String) {
  page(
    200,
    "KM Triad — Live Brain Memory",
    "/km",
    h.div([], [
      h.h1([], [h.text("#km-triad Live Brain Memory")]),
      h.ul(
        [],
        list.map(brain_roots, fn(p) {
          h.li([], [
            link(file_url(p), p),
            h.text(" • " <> int.to_string(count(root, p)) <> " live files"),
          ])
        }),
      ),
      h.ul(
        [],
        list.map([wiki_index, zk_index, triad_manifest, system_prompt], fn(p) {
          h.li([], [link(file_url(p), p)])
        }),
      ),
      h.ul(
        [],
        children(root, "governance/capability-inventory")
          |> list.filter(fn(e) { string.ends_with(e.path, "-km-index.json") })
          |> list.take(1)
          |> list.map(fn(e) {
            h.li([], [link(file_url(e.path), "Latest KM Index")])
          }),
      ),
      h.form([a.action("/api/v1/knowledge/search"), a.method("get")], [
        h.input([a.name("q"), a.placeholder("Search live corpus")]),
        h.button([], [h.text("Search")]),
      ]),
    ]),
  )
}

fn entry_json(e: Entry) -> json.Json {
  let url = file_url(e.path)
  let route = case e.path {
    "docs/wiki/" <> name -> "/wiki/" <> uri.percent_encode(name)
    "docs/zk/" <> name -> "/zk/" <> uri.percent_encode(name)
    _ -> url
  }
  json.object([
    #("path", json.string(e.path)),
    #("url", json.string(url)),
    #("raw_url", json.string(url <> "?raw=1")),
    #("tailscale_url", json.string(base_url <> url)),
    #("document_url", json.string(base_url <> route)),
    #("bytes", json.int(e.bytes)),
    #("mtime_seconds", json.int(e.mtime)),
  ])
}

fn json_response(
  status: Int,
  fields: List(#(String, json.Json)),
) -> response.Response(String) {
  response.new(status)
  |> response.set_body(json.object(fields) |> json.to_string)
  |> response.set_header("content-type", "application/json")
  |> freshness
}

fn count_fields(entries: List(Entry)) -> List(#(String, json.Json)) {
  list.map(
    [
      #("wiki_count", "docs/wiki"),
      #("zk_count", "docs/zk"),
      #("sop_count", "docs/sop"),
      #("journal_count", "docs/journal"),
      #("design_count", "docs/design"),
      #("handover_count", "docs/handover"),
      #("contracts_count", "contracts"),
    ],
    fn(pair) {
      #(pair.0, json.int(list.count(entries, fn(e) { within(e.path, pair.1) })))
    },
  )
}

fn api(
  root: String,
  path: String,
  query: Option(String),
) -> response.Response(String) {
  let entries = catalog(root)
  let common =
    list.append(count_fields(entries), [
      #("workspace_root", json.string(root)),
      #("total_allowlisted_files", json.int(list.length(entries))),
    ])
  case path {
    "api/v1/km/verify" -> {
      let checks =
        list.append(
          ["AGENTS.md", wiki_index, zk_index, triad_manifest],
          canonical_artifacts,
        )
      let missing =
        list.filter(checks, fn(p) {
          case stat(root, p) {
            Ok(e) -> e.directory
            Error(_) -> True
          }
        })
      let unreadable =
        list.filter(
          [
            "docs/wiki",
            "docs/zk",
            "docs/sop",
            "docs/design",
            "docs/journal",
            "docs/handover",
            "contracts/rules",
            "governance/capability-inventory",
            "governance/planning",
          ],
          fn(p) {
            case stat(root, p), simplifile.read_directory(root <> "/" <> p) {
              Ok(e), Ok(_) -> !e.directory
              _, _ -> True
            }
          },
        )
      let artifacts =
        entries
        |> list.filter(fn(e) { string.contains(e.path, "/20261031-1012-") })
      let tagged =
        list.all(canonical_artifacts, fn(p) {
          case read(root, p, 1_048_576) {
            Ok(text) ->
              case string.ends_with(p, ".md") {
                True -> string.contains(text, "#km-triad")
                False ->
                  json.parse(text, decode.at(["schema"], decode.string))
                  == Ok("uos.mcp-anti-brittle-fractal-km-index.v1")
              }
            Error(_) -> False
          }
        })
      let intact = missing == [] && unreadable == [] && tagged
      json_response(
        case intact {
          True -> 200
          False -> 503
        },
        list.append(common, [
          #(
            "status",
            json.string(case intact {
              True -> "verified"
              False -> "degraded"
            }),
          ),
          #("missing", json.array(missing, json.string)),
          #("unreadable", json.array(unreadable, json.string)),
          #("triad_artifacts", json.array(artifacts, entry_json)),
        ]),
      )
    }
    "api/v1/km/catalog"
    | "api/km/catalog"
    | "api/smriti/catalog"
    | "api/v1/knowledge" -> {
      let filtered =
        list.filter(entries, fn(e) {
          string.starts_with(e.path, parameter(query, "prefix"))
        })
      let limit = number(query, "limit", 200, 500) |> int.max(1)
      let offset = number(query, "offset", 0, 1_000_000)
      json_response(
        200,
        list.append(common, [
          #(
            "entries",
            json.array(
              filtered |> list.drop(offset) |> list.take(limit),
              entry_json,
            ),
          ),
          #("node_count", json.int(list.length(entries))),
          #("limit", json.int(limit)),
          #("offset", json.int(offset)),
          #(
            "truncated",
            json.bool(
              list.length(filtered) > offset + limit
              || list.length(entries) >= 20_000,
            ),
          ),
        ]),
      )
    }
    _ -> {
      let q = parameter(query, "q")
      let candidates =
        entries
        |> list.filter(fn(e) {
          list.any(
            [
              "docs/wiki",
              "docs/zk",
              "docs/sop",
              "docs/handover",
              "docs/design",
              "docs/journal",
              "contracts/rules",
            ],
            fn(r) { within(e.path, r) },
          )
          && string.ends_with(e.path, ".md")
        })
      let direct = list.filter(candidates, fn(e) { slug_matches(e.path, q) })
      let scan =
        candidates
        |> list.filter(fn(e) { !list.contains(direct, e) })
        |> list.take(int.max(0, 120 - list.length(direct)))
      let found =
        list.append(
          direct,
          list.filter(scan, fn(e) {
            case read(root, e.path, 1_048_576) {
              Ok(text) ->
                q != ""
                && string.contains(string.lowercase(text), string.lowercase(q))
              _ -> False
            }
          }),
        )
        |> list.take(120)
      let found = case path {
        "api/v1/inference/zk-transclude" if q == "" ->
          candidates
          |> list.filter(fn(e) {
            within(e.path, "docs/zk") || within(e.path, "docs/wiki")
          })
          |> list.take(120)
        _ -> found
      }
      json_response(
        200,
        list.append(common, [
          #("query", json.string(q)),
          #(
            "total_corpus_notes",
            json.int(
              list.count(entries, fn(e) {
                within(e.path, "docs/zk") || within(e.path, "docs/wiki")
              }),
            ),
          ),
          #("results", json.array(found, entry_json)),
          #("content_scan_limit", json.int(120)),
          #("truncated", json.bool(list.length(candidates) > 120)),
        ]),
      )
    }
  }
}

pub fn handles(path: String) -> Bool {
  list.any(
    ["/wiki", "/zk", "/adrs", "/km", "/knowledge-explorer", "/docs", "/files"],
    fn(r) { within(path, r) },
  )
  || list.contains(
    [
      "/api/v1/km/catalog",
      "/api/km/catalog",
      "/api/knowledge/query",
      "/api/v1/knowledge/search",
      "/api/v1/zk/search",
      "/api/v1/inference/zk-transclude",
      "/api/smriti/catalog",
      "/api/v1/knowledge",
      "/api/v1/km/verify",
    ],
    path,
  )
}

pub fn handle(
  raw_path: String,
  query: Option(String),
) -> response.Response(String) {
  let root = workspace_root()
  case decode_path(raw_path) {
    Error(code) -> failure(code, raw_path)
    Ok(path) ->
      case path {
        "wiki" ->
          root_index(
            root,
            "docs/wiki",
            "/wiki",
            query,
            "Hermes Wiki — Live Corpus",
            True,
          )
        "zk" ->
          root_index(
            root,
            "docs/zk",
            "/zk",
            query,
            "ZigVM Zettelkasten — Live Corpus",
            True,
          )
        "wiki/" <> target ->
          slug_page(root, "docs/wiki", target, raw_path, query)
        "zk/" <> target | "adrs/" <> target ->
          slug_page(root, "docs/zk", target, raw_path, query)
        "adrs" ->
          page(
            200,
            "Live ADR Index",
            raw_path,
            h.table(
              [],
              catalog(root)
                |> list.filter(fn(e) {
                  {
                    within(e.path, "docs/zk")
                    || within(e.path, "docs/architecture")
                  }
                  && string.contains(string.lowercase(e.path), "-adr-")
                  && string.ends_with(e.path, ".md")
                })
                |> list.map(entry_links),
            ),
          )
        "km" | "km/" <> _ | "knowledge-explorer" -> hub(root)
        "docs" ->
          root_index(root, "docs", "/docs", query, "Live Documentation", False)
        "docs/" <> sub -> docs_page(root, sub, raw_path, query)
        "files" ->
          listing(root, "", "/files", query, "Live Allowlisted Corpus", False)
        "files/" <> rel -> path_page(root, rel, raw_path, query)
        "api/" <> _ -> api(root, path, query)
        _ -> failure(404, raw_path)
      }
  }
}

fn root_index(
  root: String,
  rel: String,
  path: String,
  query: Option(String),
  title: String,
  explorer: Bool,
) -> response.Response(String) {
  case stat(root, rel) {
    Ok(e) if e.directory ->
      case simplifile.read_directory(root <> "/" <> rel) {
        Ok(_) -> listing(root, rel, path, query, title, explorer)
        Error(_) -> failure(403, path)
      }
    Ok(_) -> failure(403, path)
    Error(code) -> failure(code, path)
  }
}
