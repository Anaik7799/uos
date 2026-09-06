import cepaf_gleam/ui/lustre/biosemiotics_radar
import gleeunit/should

pub fn rocha_cut_status_test() {
  let radar = biosemiotics_radar.build_canonical_radar()
  radar.rocha_cut_decoupled |> should.be_true()
}

pub fn hardware_storage_lock_verified_test() {
  let radar = biosemiotics_radar.build_canonical_radar()
  radar.os_nvme_locked |> should.be_true()
  radar.os_nvme_serial |> should.equal("25503L801736")
}

pub fn lyapunov_stability_threshold_test() {
  let radar = biosemiotics_radar.build_canonical_radar()
  // Lyapunov exponent lambda must be strictly negative for asymptotic stability
  should.be_true(radar.lyapunov_lambda <. 0.0)
  should.be_true(radar.lyapunov_lambda <=. -0.05)
}

pub fn render_svg_radar_html_test() {
  let radar = biosemiotics_radar.build_canonical_radar()
  let html = biosemiotics_radar.render_svg_radar_html(radar)
  should.be_true(biosemiotics_radar.string_contains(html, "<polygon"))
  should.be_true(biosemiotics_radar.string_contains(html, "25503L801736"))
}
