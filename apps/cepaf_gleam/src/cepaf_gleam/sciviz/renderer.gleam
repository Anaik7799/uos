// renderer.gleam — Pure Gleam Lustre SVG Renderer for SciViz Plots & Flight Instruments
// Translates Grammar of Graphics, SciChart buffers, deck.gl layers, and PixiJS
// scene graphs into pure SVG elements with zero client-side JavaScript.

import cepaf_gleam/sciviz/dsl
import cepaf_gleam/sciviz/schema.{
  type GeomType, type Point2D, type SceneNode, type SciVizPlot, ArcLayer,
  GeomArea, GeomLine, GeomPhasePortrait, GeomPoint, HeatmapMatrixLayer, PathLayer,
  ScatterplotLayer, TopologyGraphLayer, VisualCircle, VisualComposite,
  VisualRect, VisualText,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/svg

pub fn render_plot(plot: SciVizPlot) -> Element(msg) {
  let w_str = float.to_string(plot.width)
  let h_str = float.to_string(plot.height)
  let viewbox = "0 0 " <> w_str <> " " <> h_str

  svg.svg(
    [
      attribute.class("sciviz-plot w-full h-auto font-mono select-none"),
      attribute.attribute("viewBox", viewbox),
    ],
    [
      render_background(plot),
      render_grid(plot),
      render_title(plot),
      render_data_geoms(plot),
      render_deck_layers(plot),
      render_scene_node(plot.scene_root),
    ],
  )
}

fn render_background(plot: SciVizPlot) -> Element(msg) {
  svg.rect([
    attribute.attribute("x", "0"),
    attribute.attribute("y", "0"),
    attribute.attribute("width", float.to_string(plot.width)),
    attribute.attribute("height", float.to_string(plot.height)),
    attribute.attribute("fill", plot.theme.bg_color),
    attribute.attribute("rx", "6"),
  ])
}

fn render_grid(plot: SciVizPlot) -> Element(msg) {
  let step_x = plot.width /. 5.0
  let step_y = plot.height /. 4.0
  let v_lines =
    list.map([1.0, 2.0, 3.0, 4.0], fn(i) {
      let x = float.to_string(i *. step_x)
      svg.line([
        attribute.attribute("x1", x),
        attribute.attribute("y1", "0"),
        attribute.attribute("x2", x),
        attribute.attribute("y2", float.to_string(plot.height)),
        attribute.attribute("stroke", plot.theme.grid_color),
        attribute.attribute("stroke-width", "1"),
        attribute.attribute("stroke-dasharray", "3 3"),
      ])
    })
  let h_lines =
    list.map([1.0, 2.0, 3.0], fn(i) {
      let y = float.to_string(i *. step_y)
      svg.line([
        attribute.attribute("x1", "0"),
        attribute.attribute("y1", y),
        attribute.attribute("x2", float.to_string(plot.width)),
        attribute.attribute("y2", y),
        attribute.attribute("stroke", plot.theme.grid_color),
        attribute.attribute("stroke-width", "1"),
        attribute.attribute("stroke-dasharray", "3 3"),
      ])
    })
  svg.g([], list.append(v_lines, h_lines))
}

fn render_title(plot: SciVizPlot) -> Element(msg) {
  svg.text(
    [
      attribute.attribute("x", "16"),
      attribute.attribute("y", "24"),
      attribute.attribute("fill", plot.theme.text_color),
      attribute.attribute("font-size", "11"),
      attribute.attribute("font-weight", "bold"),
      attribute.attribute("letter-spacing", "0.08em"),
    ],
    plot.title,
  )
}

fn render_data_geoms(plot: SciVizPlot) -> Element(msg) {
  let geom_elements =
    list.flat_map(plot.data_series, fn(series) {
      let projected_points =
        list.map(series.points, fn(p) { dsl.project_point(plot.scale, p) })
      list.map(plot.geoms, fn(geom) {
        render_single_geom(plot, geom, projected_points)
      })
    })
  svg.g([attribute.class("sciviz-geoms")], geom_elements)
}

fn render_single_geom(
  plot: SciVizPlot,
  geom: GeomType,
  points: List(Point2D),
) -> Element(msg) {
  case geom {
    GeomLine(stroke_width, color, dashed) -> {
      let points_str =
        points
        |> list.map(fn(p) {
          float.to_string(p.x) <> "," <> float.to_string(p.y)
        })
        |> string.join(" ")

      let dash_attr = case dashed {
        True -> [attribute.attribute("stroke-dasharray", "4 4")]
        False -> []
      }
      svg.polyline(
        list.append(
          [
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke", color),
            attribute.attribute("stroke-width", float.to_string(stroke_width)),
            attribute.attribute("points", points_str),
          ],
          dash_attr,
        ),
      )
    }

    GeomPoint(size, color) -> {
      let circles =
        list.map(points, fn(p) {
          svg.circle([
            attribute.attribute("cx", float.to_string(p.x)),
            attribute.attribute("cy", float.to_string(p.y)),
            attribute.attribute("r", float.to_string(size)),
            attribute.attribute("fill", color),
          ])
        })
      svg.g([], circles)
    }

    GeomArea(fill_color, opacity) -> {
      case list.is_empty(points) {
        True -> svg.g([], [])
        False -> {
          let base_y = float.to_string(plot.height)
          let points_str =
            points
            |> list.map(fn(p) {
              float.to_string(p.x) <> "," <> float.to_string(p.y)
            })
            |> string.join(" ")
          let first_x = case list.first(points) {
            Ok(p) -> float.to_string(p.x)
            Error(_) -> "0"
          }
          let last_x = case list.last(points) {
            Ok(p) -> float.to_string(p.x)
            Error(_) -> float.to_string(plot.width)
          }
          let closed_str =
            points_str
            <> " "
            <> last_x
            <> ","
            <> base_y
            <> " "
            <> first_x
            <> ","
            <> base_y
          svg.polygon([
            attribute.attribute("fill", fill_color),
            attribute.attribute("fill-opacity", float.to_string(opacity)),
            attribute.attribute("points", closed_str),
          ])
        }
      }
    }

    GeomPhasePortrait(scale_val, color) -> {
      let vectors =
        list.map(points, fn(p) {
          let target_x = p.x +. { scale_val *. 10.0 }
          let target_y = p.y -. { scale_val *. 8.0 }
          svg.line([
            attribute.attribute("x1", float.to_string(p.x)),
            attribute.attribute("y1", float.to_string(p.y)),
            attribute.attribute("x2", float.to_string(target_x)),
            attribute.attribute("y2", float.to_string(target_y)),
            attribute.attribute("stroke", color),
            attribute.attribute("stroke-width", "1.5"),
          ])
        })
      svg.g([], vectors)
    }

    _ -> svg.g([], [])
  }
}

fn render_deck_layers(plot: SciVizPlot) -> Element(msg) {
  let layer_elements =
    list.map(plot.layers, fn(layer) {
      case layer {
        ScatterplotLayer(_id, points, radius, color) -> {
          let projected = list.map(points, fn(p) { dsl.project_point(plot.scale, p) })
          let circles =
            list.map(projected, fn(p) {
              svg.circle([
                attribute.attribute("cx", float.to_string(p.x)),
                attribute.attribute("cy", float.to_string(p.y)),
                attribute.attribute("r", float.to_string(radius)),
                attribute.attribute("fill", color),
              ])
            })
          svg.g([attribute.class("deck-scatterplot")], circles)
        }

        PathLayer(_id, path, stroke_width, color) -> {
          let projected = list.map(path, fn(p) { dsl.project_point(plot.scale, p) })
          let points_str =
            projected
            |> list.map(fn(p) {
              float.to_string(p.x) <> "," <> float.to_string(p.y)
            })
            |> string.join(" ")
          svg.polyline([
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke", color),
            attribute.attribute("stroke-width", float.to_string(stroke_width)),
            attribute.attribute("points", points_str),
          ])
        }

        ArcLayer(_id, src, tgt, tilt, stroke_width, color) -> {
          let p1 = dsl.project_point(plot.scale, src)
          let p2 = dsl.project_point(plot.scale, tgt)
          let mid_x = { p1.x +. p2.x } /. 2.0
          let mid_y = { { p1.y +. p2.y } /. 2.0 } -. tilt
          let d_path =
            "M "
            <> float.to_string(p1.x)
            <> " "
            <> float.to_string(p1.y)
            <> " Q "
            <> float.to_string(mid_x)
            <> " "
            <> float.to_string(mid_y)
            <> " "
            <> float.to_string(p2.x)
            <> " "
            <> float.to_string(p2.y)
          svg.path([
            attribute.attribute("d", d_path),
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke", color),
            attribute.attribute("stroke-width", float.to_string(stroke_width)),
          ])
        }

        HeatmapMatrixLayer(_id, matrix, min_val, max_val) -> {
          let rows_count = list.length(matrix)
          let cell_h = plot.height /. int.to_float(case rows_count == 0 {
            True -> 1
            False -> rows_count
          })
          let cells =
            matrix
            |> list.index_map(fn(row, r_idx) {
              let cols_count = list.length(row)
              let cell_w = plot.width /. int.to_float(case cols_count == 0 {
                True -> 1
                False -> cols_count
              })
              list.index_map(row, fn(val, c_idx) {
                let x_pos = int.to_float(c_idx) *. cell_w
                let y_pos = int.to_float(r_idx) *. cell_h
                let norm = case max_val == min_val {
                  True -> 0.0
                  False -> { val -. min_val } /. { max_val -. min_val }
                }
                let fill_opacity = float.to_string(0.2 +. { norm *. 0.8 })
                svg.rect([
                  attribute.attribute("x", float.to_string(x_pos)),
                  attribute.attribute("y", float.to_string(y_pos)),
                  attribute.attribute("width", float.to_string(cell_w -. 1.0)),
                  attribute.attribute("height", float.to_string(cell_h -. 1.0)),
                  attribute.attribute("fill", plot.theme.primary_color),
                  attribute.attribute("fill-opacity", fill_opacity),
                ])
              })
            })
            |> list.flatten
          svg.g([attribute.class("deck-heatmap")], cells)
        }

        TopologyGraphLayer(_id, nodes, edges) -> {
          let rendered_edges =
            list.filter_map(edges, fn(e) {
              let from_node = list.drop(nodes, e.0) |> list.first
              let to_node = list.drop(nodes, e.1) |> list.first
              case from_node, to_node {
                Ok(#(_, p1)), Ok(#(_, p2)) -> {
                  let sp1 = dsl.project_point(plot.scale, p1)
                  let sp2 = dsl.project_point(plot.scale, p2)
                  Ok(
                    svg.line([
                      attribute.attribute("x1", float.to_string(sp1.x)),
                      attribute.attribute("y1", float.to_string(sp1.y)),
                      attribute.attribute("x2", float.to_string(sp2.x)),
                      attribute.attribute("y2", float.to_string(sp2.y)),
                      attribute.attribute("stroke", plot.theme.axis_color),
                      attribute.attribute("stroke-width", "1.5"),
                    ]),
                  )
                }
                _, _ -> Error(Nil)
              }
            })
          let rendered_nodes =
            list.map(nodes, fn(n) {
              let sp = dsl.project_point(plot.scale, n.1)
              svg.g([], [
                svg.circle([
                  attribute.attribute("cx", float.to_string(sp.x)),
                  attribute.attribute("cy", float.to_string(sp.y)),
                  attribute.attribute("r", "5"),
                  attribute.attribute("fill", plot.theme.accent_color),
                ]),
                svg.text(
                  [
                    attribute.attribute("x", float.to_string(sp.x +. 7.0)),
                    attribute.attribute("y", float.to_string(sp.y +. 3.0)),
                    attribute.attribute("fill", plot.theme.text_color),
                    attribute.attribute("font-size", "9"),
                  ],
                  n.0,
                ),
              ])
            })
          svg.g(
            [attribute.class("deck-topology")],
            list.append(rendered_edges, rendered_nodes),
          )
        }
      }
    })
  svg.g([attribute.class("sciviz-deck-layers")], layer_elements)
}

fn render_scene_node(node: SceneNode) -> Element(msg) {
  let visual_el = case node.visual {
    VisualCircle(cx, cy, r, fill) ->
      svg.circle([
        attribute.attribute("cx", float.to_string(cx)),
        attribute.attribute("cy", float.to_string(cy)),
        attribute.attribute("r", float.to_string(r)),
        attribute.attribute("fill", fill),
      ])
    VisualRect(x, y, w, h, fill) ->
      svg.rect([
        attribute.attribute("x", float.to_string(x)),
        attribute.attribute("y", float.to_string(y)),
        attribute.attribute("width", float.to_string(w)),
        attribute.attribute("height", float.to_string(h)),
        attribute.attribute("fill", fill),
      ])
    VisualText(x, y, content, size, color) ->
      svg.text(
        [
          attribute.attribute("x", float.to_string(x)),
          attribute.attribute("y", float.to_string(y)),
          attribute.attribute("fill", color),
          attribute.attribute("font-size", int.to_string(size)),
        ],
        content,
      )
    VisualComposite(_) -> svg.g([], [])
  }
  let children_els = list.map(node.children, fn(c) { render_scene_node(c) })
  let transform_attr =
    "translate("
    <> float.to_string(node.translate.x)
    <> " "
    <> float.to_string(node.translate.y)
    <> ") rotate("
    <> float.to_string(node.rotate_deg)
    <> ") scale("
    <> float.to_string(node.scale)
    <> ")"

  svg.g(
    [attribute.attribute("transform", transform_attr)],
    [visual_el, ..children_els],
  )
}
