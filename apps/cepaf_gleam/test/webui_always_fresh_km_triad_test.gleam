//// Hermetic read/write/delete/security falsifiers; no repository fixture writes.

import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/mcp/runtime_gateway as gateway
import cepaf_gleam/mcp/types.{Complete}
import cepaf_gleam/mcp/workspace_knowledge
import cepaf_gleam/ui/lustre/live_corpus as live
import cepaf_gleam/ui/wisp/router
import gleam/dict
import gleam/dynamic/decode
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import simplifile

pub fn relevance_ranked_token_bounded_brain_memory_search_test() {
  let direct_path = "docs/zk/20261031-1012-fractal-system-prompt.md"
  let older_path = "docs/zk/20260905-1801-corpus-index.md"
  let title = "# Older corpus index\n"
  let passage = "EXACT fractal system prompt MATCH"
  let oversized =
    title
    <> string.repeat("x", 6000)
    <> passage
    <> string.repeat(
      "y",
      10_000 - string.byte_size(title) - 6000 - string.byte_size(passage),
    )
  string.byte_size(oversized) |> should.equal(10_000)
  let corpus =
    knowledge.new_corpus("/workspace", ["public"], 20_000, 8)
    |> knowledge.with_entry(knowledge.CorpusEntry(
      direct_path,
      knowledge.RegularFile,
      "public",
      "# Fractal system prompt\nCanonical guide",
    ))
    |> knowledge.with_entry(knowledge.CorpusEntry(
      older_path,
      knowledge.RegularFile,
      "public",
      oversized,
    ))
  list.each(["knowledge_search", "zk_search", "zk_transclude"], fn(name) {
    let assert Complete(payload, _) =
      knowledge.execute(
        corpus,
        ["public"],
        name,
        dict.from_list([
          #("query", "fractal system prompt"),
          #("limit", "5"),
        ]),
      )
    let assert Ok([direct, older]) =
      json.parse(payload, decode.at(["results"], decode.list(decode.dynamic)))
    decode.run(direct, decode.at(["rel_path"], decode.string))
    |> should.equal(Ok(direct_path))
    decode.run(direct, decode.at(["content"], decode.string))
    |> should.equal(Ok("# Fractal system prompt\nCanonical guide"))
    decode.run(direct, decode.at(["truncated"], decode.bool))
    |> should.equal(Ok(False))
    decode.run(older, decode.at(["rel_path"], decode.string))
    |> should.equal(Ok(older_path))
    decode.run(older, decode.at(["truncated"], decode.bool))
    |> should.equal(Ok(True))
    let assert Ok(snippet) =
      decode.run(older, decode.at(["content"], decode.string))
    string.length(snippet) |> should.equal(2400)
    contains(snippet, title)
    contains(snippet, passage)
    decode.run(older, decode.at(["bytes"], decode.int))
    |> should.equal(Ok(10_000))
    list.each([#(direct, direct_path), #(older, older_path)], fn(hit) {
      decode.run(hit.0, decode.at(["tailscale_url"], decode.string))
      |> should.equal(Ok(live.base_url <> "/files/" <> hit.1))
      decode.run(hit.0, decode.at(["resource_uri"], decode.string))
      |> should.equal(
        Ok(case hit.1 {
          "docs/" <> rest -> "uos://docs/" <> rest
          path -> "uos://km/" <> path
        }),
      )
    })
  })
  // Even an exact path supplied as a query must use the bounded search shape.
  let assert Complete(payload, _) =
    knowledge.execute(
      corpus,
      ["public"],
      "zk_transclude",
      dict.from_list([
        #("query", older_path),
      ]),
    )
  let assert Ok([hit]) =
    json.parse(payload, decode.at(["results"], decode.list(decode.dynamic)))
  decode.run(hit, decode.at(["truncated"], decode.bool))
  |> should.equal(Ok(True))
}

@external(erlang, "live_corpus_test_ffi", "fixture")
fn with_temp(run: fn(String) -> Nil) -> Nil

pub fn brain_memory_grapheme_boundaries_and_newest_tie_test() {
  list.each([2400, 2401, 10_000], fn(size) {
    let header = "# Memory title\n"
    let content =
      header <> string.repeat("🧠", size - string.length(header) - 6) <> "needle"
    let older = "docs/zk/20260905-1801-memory.md"
    let newer = "docs/zk/20261031-1012-memory.md"
    let corpus =
      knowledge.new_corpus("/workspace", ["public"], 50_000, 8)
      |> knowledge.with_entry(knowledge.CorpusEntry(
        older,
        knowledge.RegularFile,
        "public",
        content,
      ))
      |> knowledge.with_entry(knowledge.CorpusEntry(
        newer,
        knowledge.RegularFile,
        "public",
        content,
      ))
    let assert Complete(payload, _) =
      knowledge.execute(
        corpus,
        ["public"],
        "knowledge_search",
        dict.from_list([#("query", "needle")]),
      )
    let assert Ok([first, second]) =
      json.parse(payload, decode.at(["results"], decode.list(decode.dynamic)))
    decode.run(first, decode.at(["rel_path"], decode.string))
    |> should.equal(Ok(newer))
    list.each([first, second], fn(hit) {
      let assert Ok(snippet) =
        decode.run(hit, decode.at(["content"], decode.string))
      string.length(snippet) |> should.equal(2400)
      string.starts_with(snippet, header) |> should.be_true
      contains(snippet, "needle")
      decode.run(hit, decode.at(["bytes"], decode.int))
      |> should.equal(Ok(string.byte_size(content)))
      decode.run(hit, decode.at(["truncated"], decode.bool))
      |> should.equal(Ok(size > 2400))
      case size == 2400 {
        True -> snippet |> should.equal(content)
        False -> Nil
      }
    })
  })
}

@external(erlang, "live_corpus_test_ffi", "symlink")
fn symlink(target: String, link: String) -> Nil

@external(erlang, "live_corpus_test_ffi", "hardlink")
fn hardlink(target: String, link: String) -> Nil

@external(erlang, "live_corpus_test_ffi", "fifo")
fn fifo(path: String) -> Nil

@external(erlang, "live_corpus_test_ffi", "parallel")
fn parallel(run: fn(Int) -> Nil) -> Bool

@external(erlang, "live_corpus_test_ffi", "swap_race")
fn swap_race(root: String, read: fn() -> Nil) -> Bool

@external(erlang, "live_corpus_test_ffi", "restart_workers")
fn restart_workers() -> Int

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn nanos() -> Int

fn put(root: String, path: String, content: String) {
  let parent =
    string.split(path, "/")
    |> list.reverse
    |> list.drop(1)
    |> list.reverse
    |> string.join("/")
  let assert Ok(_) = simplifile.create_directory_all(root <> "/" <> parent)
  let assert Ok(_) = simplifile.write(root <> "/" <> path, content)
  Nil
}

fn fixture(run: fn(String) -> Nil) {
  with_temp(fn(root) {
    list.each(
      [
        "docs/wiki",
        "docs/zk",
        "docs/sop",
        "docs/design",
        "docs/journal",
        "docs/handover",
        "docs/architecture",
        "contracts/rules",
        "governance/capability-inventory",
        "governance/planning",
      ],
      fn(p) {
        let assert Ok(_) = simplifile.create_directory_all(root <> "/" <> p)
        Nil
      },
    )
    list.each(
      list.append(
        ["AGENTS.md", live.wiki_index, live.zk_index, live.triad_manifest],
        live.canonical_artifacts,
      ),
      fn(p) {
        put(root, p, case string.ends_with(p, ".json") {
          True -> "{\"schema\":\"uos.mcp-anti-brittle-fractal-km-index.v1\"}"
          False -> "#km-triad canonical " <> p
        })
      },
    )
    list.each(
      [
        "registry",
        "admission",
        "receipts",
        "dispatch",
        "route_convergence",
        "server",
      ],
      fn(name) {
        let assert Ok(bytes) =
          simplifile.read("src/cepaf_gleam/mcp/" <> name <> ".gleam")
        put(
          root,
          "apps/cepaf_gleam/src/cepaf_gleam/mcp/" <> name <> ".gleam",
          bytes,
        )
      },
    )
    run(root)
  })
}

fn get(target: String) -> response.Response(String) {
  request.to("http://nas-1.tail55d152.ts.net:4100" <> target)
  |> should.be_ok
  |> request.set_body("")
  |> router.handle_request
}

fn contains(body: String, text: String) {
  case string.contains(body, text) {
    True -> Nil
    False -> {
      io.println("EXPECTED " <> text <> " ACTUAL " <> body)
      should.equal(body, "Expected to contain: " <> text)
    }
  }
}

fn fresh(res: response.Response(String)) {
  response.get_header(res, "cache-control")
  |> should.be_ok
  |> contains("no-store")
  response.get_header(res, "x-uos-freshness") |> should.equal(Ok("live-disk"))
}

pub fn zero_staleness_create_modify_delete_exact_bytes_and_digest_test() {
  fixture(fn(root) {
    let rel = "docs/wiki/20261031-9999-fresh-test.md"
    get("/wiki/20261031-9999-fresh-test.md").status |> should.equal(404)
    list.each(
      ["v1 token oauth <script>escaped()</script>", "v2 immediately changed"],
      fn(content) {
        put(root, rel, content)
        list.each(
          [
            "/wiki/20261031-9999-fresh-test.md",
            "/files/" <> rel,
            "/files/" <> rel <> "?raw=1",
          ],
          fn(url) {
            let res = get(url)
            res.status |> should.equal(200)
            fresh(res)
            response.get_header(res, "x-uos-content-sha256")
            |> should.equal(Ok(live.sha256(content)))
            case string.contains(url, "raw=1") {
              True -> res.body |> should.equal(content)
              False ->
                contains(res.body, case content {
                  "v2 immediately changed" -> content
                  _ -> "v1 token oauth"
                })
            }
          },
        )
      },
    )
    let assert Ok(_) = simplifile.delete(root <> "/" <> rel)
    get("/wiki/20261031-9999-fresh-test.md").status |> should.equal(404)
    get("/files/" <> rel).status |> should.equal(404)
  })
}

pub fn path_link_special_file_size_and_xss_falsifiers_test() {
  fixture(fn(root) {
    list.each(
      [
        "/files/var/sa-plan/uos.sqlite3",
        "/files/.jj/repo/store",
        "/files/../../etc/passwd",
        "/files/docs/%2e%2e/var/x",
        "/files/docs/%252e%252e/x",
        "/files/docs/x%2Fy.md",
        "/files/docs/x%5Cy.md",
        "/files/docs/x%00.md",
        "/files/docs/x%7f.md",
        "/files/docs/credentials.md",
      ],
      fn(path) {
        let #(raw, q) = live.split_target(path)
        live.handle(raw, q).status |> should.equal(403)
      },
    )
    symlink("/etc/hostname", root <> "/docs/wiki/evil.md")
    get("/files/docs/wiki/evil.md").status |> should.equal(403)
    symlink("/etc", root <> "/docs/wiki/escape")
    get("/files/docs/wiki/escape/hostname.txt").status |> should.equal(403)
    put(root, "docs/wiki/original.md", "hard")
    hardlink(root <> "/docs/wiki/original.md", root <> "/docs/wiki/hard.md")
    get("/files/docs/wiki/hard.md").status |> should.equal(403)
    fifo(root <> "/docs/wiki/pipe.md")
    get("/files/docs/wiki/pipe.md").status |> should.equal(403)
    put(root, "docs/wiki/big.md", string.repeat("x", 4_194_305))
    get("/files/docs/wiki/big.md").status |> should.equal(413)
    put(root, "docs/wiki/what?.md", "literal question")
    let raw = get("/files/docs/wiki/what%3F.md?raw=1")
    raw.status |> should.equal(200)
    raw.body |> should.equal("literal question")
    response.get_header(raw, "content-type")
    |> should.equal(Ok("text/plain; charset=utf-8"))
    response.get_header(raw, "content-security-policy")
    |> should.equal(Ok("sandbox"))
    let escaped = live.handle("/docs/<script>alert(1)</script>", option.None)
    escaped.status |> should.equal(404)
    string.contains(escaped.body, "<script>alert(1)</script>")
    |> should.be_false
    contains(escaped.body, "&lt;script&gt;")
    contains(escaped.body, "checklist")
    contains(escaped.body, "<nav")
    get("/kms").status |> should.equal(200)
    string.contains(get("/kms?v=1").body, "C3I — Not Found") |> should.be_false
    live.handles("/kms") |> should.be_false
  })
}

pub fn corpus_routes_slug_boundaries_search_pagination_and_verify_test() {
  fixture(fn(root) {
    put(root, "docs/zk/20261031-1000-adr-012-boundary.md", "needle twelve")
    put(root, "docs/zk/20261031-1000-adr-0120-boundary.md", "wrong one twenty")
    put(root, "docs/wiki/20261031-1000-ambiguous-a.md", "needle")
    put(root, "docs/wiki/20261031-1000-ambiguous-b.md", "needle")
    list.each(
      [
        "/wiki",
        "/zk",
        "/km",
        "/adrs",
        "/docs",
        "/docs/wiki",
        "/files",
        "/files/AGENTS.md",
        "/docs/contracts/rules",
        "/docs/docs/wiki",
        "/knowledge-explorer",
      ],
      fn(path) {
        let res = get(path)
        res.status |> should.equal(200)
        fresh(res)
      },
    )
    let boundary = get("/zk/ADR-012")
    boundary.status |> should.equal(200)
    contains(boundary.body, "needle twelve")
    string.contains(boundary.body, "wrong one twenty") |> should.be_false
    get("/wiki/ambiguous").status |> should.equal(300)
    get("/wiki/no-such-slug").status |> should.equal(404)
    get("/docs/no-such-document").status |> should.equal(404)
    let cat = get("/api/v1/km/catalog?limit=5&offset=0")
    json.parse(cat.body, decode.at(["truncated"], decode.bool))
    |> should.equal(Ok(True))
    json.parse(cat.body, decode.at(["entries"], decode.list(decode.dynamic)))
    |> should.be_ok
    |> list.length
    |> should.equal(5)
    list.each(
      [
        "/api/knowledge/query?q=needle",
        "/api/v1/knowledge/search?q=needle",
        "/api/v1/zk/search?q=needle",
        "/api/v1/inference/zk-transclude",
        "/api/smriti/catalog",
        "/api/v1/knowledge",
      ],
      fn(path) {
        let res = get(path)
        res.status |> should.equal(200)
        fresh(res)
        contains(res.body, "http://nas-1.tail55d152.ts.net:4100/files/")
      },
    )
    get("/api/v1/km/verify").status |> should.equal(200)
    let assert Ok(_) = simplifile.delete(root <> "/" <> live.wiki_index)
    get("/api/v1/km/verify").status |> should.equal(503)
  })
}

pub fn rendered_links_allow_safe_urls_and_preserve_prose_test() {
  fixture(fn(root) {
    put(
      root,
      "docs/wiki/links.md",
      "[[wiki:target|Master Index]] [[zk:ADR-012|@supports]] [web](https://example.com) [bad](javascript:alert) <script>evil()</script>",
    )
    let res = get("/files/docs/wiki/links.md")
    contains(res.body, "href=\"/wiki/target\"")
    contains(res.body, "href=\"/zk/ADR-012\"")
    contains(res.body, "href=\"https://example.com\"")
    string.contains(res.body, "href=\"javascript:") |> should.be_false
    string.contains(res.body, "<script>evil()</script>") |> should.be_false
  })
}

fn mcp(root: String, method: String, params: json.Json) -> String {
  let raw =
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(1)),
      #("method", json.string(method)),
      #("params", params),
    ])
    |> json.to_string
  let assert Some(frame) =
    gateway.handle_standard_mcp_line(
      "codex",
      "codex",
      root,
      "fresh-test-" <> root,
      "public",
      raw,
      nanos() / 1_000_000,
    )
  frame
}

fn tool(root: String, name: String, args: List(#(String, String))) -> String {
  mcp(
    root,
    "tools/call",
    json.object([
      #("name", json.string(name)),
      #(
        "arguments",
        json.object(list.map(args, fn(p) { #(p.0, json.string(p.1)) })),
      ),
    ]),
  )
}

fn resource(root: String, uri: String) -> String {
  mcp(root, "resources/read", json.object([#("uri", json.string(uri))]))
}

pub fn search_resource_uri_dereferences_exact_document_bytes_test() {
  fixture(fn(root) {
    list.each(
      [
        "docs/sop/resource-roundtrip.md",
        "AGENTS.md",
        "contracts/rules/resource-roundtrip.md",
        "formal/lean/ResourceRoundtrip.lean",
        ".agents/skills/uos-km-triad-brain-memory/SKILL.md",
      ],
      fn(path) {
        let bytes =
          "# resourceuniqueneedle\n🧠 \"exact\" bytes\n" <> path <> "\n"
        put(root, path, bytes)
        let searched = tool(root, "knowledge_search", [#("query", path)])
        let assert Ok([payload]) =
          json.parse(
            searched,
            decode.at(
              ["result", "content"],
              decode.list(decode.at(["text"], decode.string)),
            ),
          )
        let assert Ok(hits) =
          json.parse(
            payload,
            decode.at(["results"], decode.list(decode.dynamic)),
          )
        let assert Ok(hit) =
          list.find(hits, fn(hit) {
            decode.run(hit, decode.at(["rel_path"], decode.string)) == Ok(path)
          })
        let assert Ok(uri) =
          decode.run(hit, decode.at(["resource_uri"], decode.string))
        uri
        |> should.equal(case path {
          "docs/" <> rest -> "uos://docs/" <> rest
          _ -> "uos://km/" <> path
        })
        list.each([uri, "uos://docs/" <> path, "uos://km/" <> path], fn(alias) {
          json.parse(
            resource(root, alias),
            decode.at(
              ["result", "contents"],
              decode.list(decode.at(["text"], decode.string)),
            ),
          )
          |> should.equal(Ok([bytes]))
        })
      },
    )
    list.each(["uos://docs/var/private.md", "uos://km/var/private.md"], fn(uri) {
      contains(resource(root, uri), "RESOURCE_NOT_FOUND")
    })
  })
}

pub fn mcp_brain_memory_live_search_read_transclusion_resources_and_health_test() {
  fixture(fn(root) {
    put(
      root,
      "docs/sop/brain.md",
      "brainunique v1 [[wiki:linked|Master Index]] [[zk:ADR-012|@supports]]",
    )
    put(root, "docs/wiki/linked.md", "wikiexpanded")
    put(root, "docs/zk/20261031-1000-adr-012-linked.md", "zkexpanded")
    let searched = tool(root, "knowledge_search", [#("query", "brainunique")])
    contains(searched, "docs/sop/brain.md")
    let expanded = tool(root, "zk_transclude", [#("key", "docs/sop/brain.md")])
    contains(expanded, "wikiexpanded")
    contains(expanded, "zkexpanded")
    contains(
      tool(root, "read_file", [#("path", "docs/sop/brain.md")]),
      "brainunique v1",
    )
    contains(resource(root, "uos://docs/sop/brain.md"), "brainunique v1")
    put(root, "docs/sop/brain.md", "brainunique v2")
    contains(
      tool(root, "read_file", [#("path", "docs/sop/brain.md")]),
      "brainunique v2",
    )
    contains(resource(root, "uos://docs/sop/brain.md"), "brainunique v2")
    let listed = mcp(root, "resources/list", json.object([]))
    list.each(
      [
        "uos://system/mcp-gateway-health",
        "uos://governance/ev-provenance-ceiling",
        "uos://planning/active-cutover-plan",
        "uos://km/triad",
        "uos://wiki/index",
        "uos://zk/master-moc",
        "uos://sop/fractal-system-prompt",
      ],
      fn(uri) { contains(listed, uri) },
    )
    let templates = mcp(root, "resources/templates/list", json.object([]))
    list.each(
      [
        "uos://docs/{slug}",
        "uos://wiki/{slug}",
        "uos://zk/{slug}",
        "uos://km/{path}",
      ],
      fn(uri) { contains(templates, uri) },
    )
    contains(
      mcp(root, "prompts/list", json.object([])),
      "uos_km_brain_memory_orient",
    )
    contains(
      mcp(
        root,
        "prompts/get",
        json.object([#("name", json.string("uos_km_brain_memory_orient"))]),
      ),
      "advisory_only",
    )
    contains(resource(root, "uos://km/triad"), "#km-triad")
    contains(resource(root, "uos://wiki/index"), "#km-triad")
    contains(resource(root, "uos://not-a-resource"), "RESOURCE_NOT_FOUND")
    list.each(["system_health", "ooda_decide"], fn(name) {
      let frame = tool(root, name, [])
      contains(frame, "km_brain_memory_status")
      contains(frame, "healthy")
    })
    let assert Ok(_) = simplifile.delete(root <> "/" <> live.wiki_index)
    contains(tool(root, "system_health", []), "degraded")
    workspace_knowledge.brain_memory_health_metrics(root)
    |> dict.from_list
    |> dict.get("km_canonical_triad_intact")
    |> should.equal(Ok("false"))
    let assert Ok(_) = simplifile.delete(root <> "/docs/sop/brain.md")
    string.contains(resource(root, "uos://docs/sop/brain.md"), "brainunique v2")
    |> should.be_false
    string.contains(
      tool(root, "read_file", [#("path", "docs/sop/brain.md")]),
      "brainunique v2",
    )
    |> should.be_false
    list.each(
      [
        "docs/unscoped.md",
        "var/private.md",
        ".jj/private.md",
        "docs/sop/credentials.md",
      ],
      fn(path) {
        put(root, path, "SHOULDNEVERSERVE")
        string.contains(
          tool(root, "read_file", [#("path", path)]),
          "SHOULDNEVERSERVE",
        )
        |> should.be_false
      },
    )
  })
}

pub fn thirty_two_concurrent_read_search_modify_processes_do_not_crash_test() {
  fixture(fn(root) {
    parallel(fn(n) {
      let path = "docs/wiki/concurrent-" <> int.to_string(n) <> ".md"
      put(root, path, "concurrent v1")
      get("/files/" <> path <> "?raw=1").body |> should.equal("concurrent v1")
      put(root, path, "concurrent v2")
      get("/files/" <> path <> "?raw=1").body |> should.equal("concurrent v2")
      get("/api/v1/knowledge/search?q=concurrent").status |> should.equal(200)
      let assert Ok(_) = simplifile.delete(root <> "/" <> path)
      get("/files/" <> path).status |> should.equal(404)
      Nil
    })
    |> should.be_true
  })
}

pub fn mcp_memory_survives_actual_supervised_owner_kill_test() {
  fixture(fn(root) {
    put(root, "docs/sop/restart.md", "before-worker-kill")
    contains(
      tool(root, "read_file", [#("path", "docs/sop/restart.md")]),
      "before-worker-kill",
    )
    restart_workers() |> should.equal(1)
    put(root, "docs/sop/restart.md", "after-worker-kill")
    contains(
      tool(root, "read_file", [#("path", "docs/sop/restart.md")]),
      "after-worker-kill",
    )
    contains(resource(root, "uos://docs/sop/restart.md"), "after-worker-kill")
    contains(tool(root, "system_health", []), "healthy")
  })
}

pub fn stat_only_directory_pagination_and_digest_known_vector_test() {
  fixture(fn(root) {
    live.sha256("abc")
    |> should.equal(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    )
    let _ =
      int.range(1, 205, Nil, fn(_, n) {
        put(root, "docs/handover/page-" <> int.to_string(n) <> ".md", "page")
      })
    let first = get("/docs/handover")
    first.status |> should.equal(200)
    contains(first.body, "truncated")
    contains(first.body, "offset=200")
    let next = get("/docs/handover?offset=200")
    next.status |> should.equal(200)
    string.contains(next.body, "truncated") |> should.be_false
    let assert Ok(_) = simplifile.delete(root <> "/" <> live.system_prompt)
    get("/api/v1/km/verify").status |> should.equal(503)
  })
}

pub fn query_bearing_service_worker_aliases_remain_javascript_and_uncached_test() {
  list.each(["/sw.js?v=1", "/static/sw.js?v=1"], fn(path) {
    let res = get(path)
    response.get_header(res, "content-type")
    |> should.equal(Ok("application/javascript"))
    fresh(res)
    contains(res.body, "c3i-planning-v2-20261031")
  })
}

pub fn mcp_search_normalizes_wiki_tokens_and_exact_adr_boundary_test() {
  fixture(fn(root) {
    put(root, "docs/wiki/linked.md", "uniquewikiword")
    put(root, "docs/zk/20261031-1000-adr-012-one.md", "adrtwelve")
    put(root, "docs/zk/20261031-1000-adr-0120-other.md", "adrwrong")
    contains(
      tool(root, "knowledge_search", [
        #("query", "[[wiki:linked|Master Index]]"),
      ]),
      "docs/wiki/linked.md",
    )
    let frame =
      tool(root, "knowledge_search", [#("query", "[[zk:ADR-012|@supports]]")])
    contains(frame, "adr-012-one.md")
    string.contains(frame, "adr-0120-other.md") |> should.be_false
    contains(resource(root, "uos://wiki/linked"), "uniquewikiword")
    contains(resource(root, "uos://zk/ADR-012"), "adrtwelve")
  })
}

pub fn descriptor_anchoring_refuses_concurrent_ancestor_symlink_swap_test() {
  fixture(fn(root) {
    put(root, "docs/wiki/raced/note.md", "LOCAL_ONLY")
    put(root, "outside/note.md", "FOREIGN_NEVER_SERVE")
    swap_race(root, fn() {
      let res = get("/files/docs/wiki/raced/note.md?raw=1")
      case res.status {
        200 -> res.body |> should.equal("LOCAL_ONLY")
        _ -> list.contains([403, 404], res.status) |> should.be_true
      }
    })
    |> should.be_true
  })
}

pub fn brain_catalog_excludes_unrelated_skills_without_changing_web_catalog_test() {
  fixture(fn(root) {
    let canonical = ".agents/skills/uos-km-triad-brain-memory/SKILL.md"
    let unrelated = ".agents/skills/unrelated/SKILL.md"
    put(root, canonical, "canonical brain skill")
    put(root, unrelated, "unrelated skill")
    let paths = live.brain_catalog(root) |> list.map(fn(e) { e.path })
    list.contains(paths, canonical) |> should.be_true
    list.contains(paths, unrelated) |> should.be_false
    live.catalog(root)
    |> list.any(fn(e) { e.path == unrelated })
    |> should.be_true
  })
}

pub fn brain_prefetch_prioritizes_query_words_across_thirteen_roots_beyond_120_test() {
  fixture(fn(root) {
    list.each(live.brain_roots, fn(directory) {
      list.each([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], fn(n) {
        put(root, directory <> "/zz-unrelated-" <> int.to_string(n) <> ".md", "unrelated")
      })
      put(root, directory <> "/000-needle-alpha-beta.md", "needle alpha beta")
    })
    let recalled = workspace_knowledge.prefetch_brain_memory(root, "needle\talpha\nbeta")
    list.each(live.brain_roots, fn(directory) {
      list.any(recalled, fn(e) { e.rel_path == directory <> "/000-needle-alpha-beta.md" })
      |> should.be_true
    })
    should.be_true(list.length(recalled) <= 64)
  })
}

pub fn brain_reference_expansion_stops_at_three_levels_test() {
  fixture(fn(root) {
    put(root, "docs/wiki/chain-start.md", "[[wiki:chain-1]]")
    list.each([1, 2, 3, 4], fn(n) {
      put(root, "docs/wiki/chain-" <> int.to_string(n) <> ".md", "[[wiki:chain-" <> int.to_string(n + 1) <> "]]")
    })
    let recalled = workspace_knowledge.prefetch_brain_memory(root, "chain-start")
    list.any(recalled, fn(e) { e.rel_path == "docs/wiki/chain-3.md" }) |> should.be_true
    list.any(recalled, fn(e) { e.rel_path == "docs/wiki/chain-4.md" }) |> should.be_false
  })
}
