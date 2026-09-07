import gleam/list
import gleam/string
import gleeunit/should
import uos_swarm/holon
import uos_swarm/holon_km
import uos_swarm/system_ontology

const stamp = "20260907-1645"

pub fn page_count_equals_holarchy_length_plus_one_test() {
  let pages = holon_km.pages(stamp)
  list.length(pages) |> should.equal(list.length(holon.holarchy()) + 1)
}

pub fn every_page_path_has_stamp_prefix_and_md_suffix_test() {
  let pages = holon_km.pages(stamp)
  list.each(pages, fn(pair) {
    let #(path, _md) = pair
    let basename = case string.split(path, "/") {
      [] -> path
      parts ->
        case list.last(parts) {
          Ok(b) -> b
          Error(_) -> path
        }
    }
    string.starts_with(basename, stamp) |> should.be_true
    string.ends_with(path, ".md") |> should.be_true
  })
}

pub fn every_page_carries_required_tags_links_and_nav_test() {
  let pages = holon_km.pages(stamp)
  list.each(pages, fn(pair) {
    let #(path, md) = pair
    string.contains(md, "#fractal-l") |> should.be_true
    string.contains(md, "#km-triad") |> should.be_true
    string.contains(md, "#rocha-semiotics") |> should.be_true
    string.contains(md, "#cybernetics") |> should.be_true
    string.contains(md, "#zero-muda") |> should.be_true
    string.contains(md, "#zk-adr") |> should.be_true
    string.contains(md, "http://nas-1.tail55d152.ts.net:4100/files/" <> path)
    |> should.be_true
    string.contains(md, "[[zk:20260905-1801-moc-uos-unified-master]]")
    |> should.be_true
    string.contains(md, "[[wiki:20260905-1801-uos-zk-km-corpus-index]]")
    |> should.be_true
    string.contains(md, "CHK-18") |> should.be_true
    string.contains(md, "http://nas-1.tail55d152.ts.net:4100/zk")
    |> should.be_true
    string.contains(md, "http://nas-1.tail55d152.ts.net:4100/wiki")
    |> should.be_true
  })
}

pub fn moc_mentions_every_holon_id_exactly_once_as_a_link_test() {
  let pages = holon_km.pages(stamp)
  let assert Ok(#(_path, moc_md)) =
    list.find(pages, fn(pair) { pair.0 == holon_km.moc_path(stamp) })
  list.each(holon.holarchy(), fn(h) {
    let link =
      "["
      <> h.id
      <> "](http://nas-1.tail55d152.ts.net:4100/files/"
      <> holon_km.holon_page_path(stamp, h.id)
      <> ")"
    count_occurrences(moc_md, link) |> should.equal(1)
  })
}

fn count_occurrences(haystack: String, needle: String) -> Int {
  case string.split(haystack, needle) {
    parts -> list.length(parts) - 1
  }
}

pub fn generation_is_deterministic_test() {
  holon_km.pages(stamp) |> should.equal(holon_km.pages(stamp))
}

pub fn ontology_contains_the_10_new_concepts_test() {
  let ids = [
    "holon-meta:holon", "holon-meta:holarchy", "holon-meta:constitution",
    "holon-meta:census", "holon-meta:lifecycle", "holon-meta:vitals",
    "holon-meta:plane", "holon-meta:whole", "holon-meta:part",
    "holon-meta:level",
  ]
  list.each(ids, fn(id) {
    case system_ontology.resolve(id) {
      Ok(_) -> Nil
      Error(_) -> should.fail()
    }
  })
}
