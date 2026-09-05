//// CLI render module — call via: gleam run -m cepaf_gleam/render_cli

import gleam/io

@external(erlang, "graphene_nif", "resvg_render_file")
fn resvg_file(svg: String, png: String, width: Int) -> Result(String, String)

@external(erlang, "graphene_nif", "plotters_chart")
fn plotters(chart_type: String, params: String) -> Result(String, String)

pub fn main() {
  io.println("C3I Render CLI — resvg + plotters pipeline")

  // Render SVG poster to 4K PNG via resvg
  case
    resvg_file(
      "/home/an/dev/ver/c3i/docs/wireframes/evolution-story.svg",
      "/home/an/dev/ver/c3i/docs/wireframes/evolution-resvg-4k.png",
      3840,
    )
  {
    Ok(r) -> io.println("resvg 4K: " <> r)
    Error(e) -> io.println("resvg error: " <> e)
  }

  // Render a plotters line chart
  case
    plotters(
      "line",
      "{\"title\":\"Health Trajectory\",\"width\":800,\"height\":400,\"data\":[{\"x\":0,\"y\":72},{\"x\":1,\"y\":74},{\"x\":2,\"y\":78},{\"x\":3,\"y\":82},{\"x\":4,\"y\":85},{\"x\":5,\"y\":88},{\"x\":6,\"y\":90},{\"x\":7,\"y\":92}]}",
    )
  {
    Ok(_) -> io.println("plotters: rendered")
    Error(e) -> io.println("plotters error: " <> e)
  }

  io.println("Pipeline complete.")
}
