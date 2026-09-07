import cepaf_gleam/knowledge/rag_cache_mesh
import cepaf_gleam/ui/lustre/rag_cache_hud
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn init_rag_cache_hud_test() {
  let hud = rag_cache_hud.init_rag_cache_hud()
  hud.cycle_id |> should.equal("EV-103")
  hud.os_nvme_serial |> should.equal("25503L801736")
  hud.os_nvme_locked |> should.equal(True)
  hud.sovereigns.quorum_fraction |> should.equal("3/3")
  should.be_true(hud.hit_ratio >. 0.8)
}

pub fn update_from_mesh_test() {
  let hud = rag_cache_hud.init_rag_cache_hud()
  let mesh = rag_cache_mesh.new(20, 0.9)
  let mesh =
    rag_cache_mesh.put(
      mesh,
      "t1",
      "test query",
      [1.0, 0.0],
      "test resp",
      [],
      500,
      1000,
      3600,
    )
  let mesh = rag_cache_mesh.record_hit(mesh, "t1", 1050)

  let updated = rag_cache_hud.update_from_mesh(hud, mesh)
  updated.entry_count |> should.equal(1)
  updated.capacity |> should.equal(20)
  updated.total_hits |> should.equal(1)
  updated.tokens_saved |> should.equal(500)
  should.be_true(updated.cost_saved_usd >. 0.0)
}

pub fn render_svg_and_html_test() {
  let hud = rag_cache_hud.init_rag_cache_hud()
  let svg = rag_cache_hud.render_hud_svg(hud)
  should.be_true(string.contains(svg, "<svg"))
  should.be_true(string.contains(svg, "EV-103"))
  should.be_true(string.contains(svg, "CACHE HIT RATIO"))
  should.be_true(string.contains(svg, "TOKEN SAVINGS"))
  should.be_true(string.contains(svg, "25503L801736"))

  let html = rag_cache_hud.render_html_page(hud)
  should.be_true(string.contains(html, "<!DOCTYPE html>"))
  should.be_true(string.contains(html, "http://nas-1.tail55d152.ts.net:4100"))
  should.be_true(string.contains(html, "Comprehensive Verification Checklist"))

  let ansi = rag_cache_hud.render_ansi(hud)
  should.be_true(string.contains(ansi, "EV-103"))
  should.be_true(string.contains(ansi, "25503L801736"))
}
