import cepaf_gleam/ui/lustre/tensor_fractal_atlas
import gleeunit/should

pub fn tensor_layers_count_test() {
  let atlas = tensor_fractal_atlas.build_canonical_atlas()
  tensor_fractal_atlas.layer_count(atlas)
  |> should.equal(10)
  // L0 through L9
}

pub fn tcm_13d_conservation_test() {
  let atlas = tensor_fractal_atlas.build_canonical_atlas()
  atlas.delta_t13
  |> should.equal(0.0)
  // Invariant Delta T_13 = 0.0
}

pub fn render_svg_tensor_matrix_test() {
  let atlas = tensor_fractal_atlas.build_canonical_atlas()
  let html = tensor_fractal_atlas.render_svg_tensor_matrix(atlas)
  should.be_true(tensor_fractal_atlas.string_contains(html, "<svg"))
  should.be_true(tensor_fractal_atlas.string_contains(html, "L0_CONSTITUTIONAL"))
  should.be_true(tensor_fractal_atlas.string_contains(
    html,
    "L9_TRANS_KNOWLEDGE",
  ))
}
