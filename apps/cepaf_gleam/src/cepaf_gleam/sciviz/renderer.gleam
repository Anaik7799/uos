// renderer.gleam — Pure Gleam Lustre SVG Renderer for SciViz Plots & Flight Instruments
// Translates Grammar of Graphics, SciChart buffers, deck.gl layers, and PixiJS
// scene graphs into pure SVG elements with zero client-side JavaScript.

import cepaf_gleam/sciviz/dsl
import cepaf_gleam/sciviz/schema.{
  type GeomType, type Point2D, type SceneNode, type SciVizPlot, ArcLayer,
  BitmapLayer, ColumnLayer, GeoJsonLayer, GeomArea, GeomBar, GeomBoxplot,
  GeomContour, GeomDensity2D, GeomErrorBar, GeomHex, GeomLine,
  GeomPhasePortrait, GeomPoint, GeomRibbon, GeomSegment, GeomStep, GeomText,
  Point2D,
  GeomViolin, GridLayer, H3HexagonLayer, HeatmapMatrixLayer, HexagonLayer,
  IconLayer, LineLayer, PathLayer, PointCloudLayer, S2Layer, ScatterplotLayer,
  ScreenGridLayer, TextLayer, TileLayer, TopologyGraphLayer, TripsLayer,
  VisualCircle, VisualComposite, VisualMesh, VisualNineSlicePlane,
  VisualParticleContainer, VisualRect, VisualSprite, VisualText,
  VisualTilingSprite,
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
      attribute.attribute("viewBox", viewbox),
      attribute.attribute("width", w_str),
      attribute.attribute("height", h_str),
      attribute.class("sciviz-plot w-full h-auto font-mono select-none"),
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
  ])
}

fn render_grid(plot: SciVizPlot) -> Element(msg) {
  let x_steps = [0.25, 0.5, 0.75]
  let y_steps = [0.25, 0.5, 0.75]

  let v_lines =
    list.map(x_steps, fn(step) {
      let x_pos = float.to_string(plot.width *. step)
      svg.line([
        attribute.attribute("x1", x_pos),
        attribute.attribute("y1", "0"),
        attribute.attribute("x2", x_pos),
        attribute.attribute("y2", float.to_string(plot.height)),
        attribute.attribute("stroke", plot.theme.grid_color),
        attribute.attribute("stroke-width", "1"),
        attribute.attribute("stroke-dasharray", "2 4"),
      ])
    })

  let h_lines =
    list.map(y_steps, fn(step) {
      let y_pos = float.to_string(plot.height *. step)
      svg.line([
        attribute.attribute("x1", "0"),
        attribute.attribute("y1", y_pos),
        attribute.attribute("x2", float.to_string(plot.width)),
        attribute.attribute("y2", y_pos),
        attribute.attribute("stroke", plot.theme.grid_color),
        attribute.attribute("stroke-width", "1"),
        attribute.attribute("stroke-dasharray", "2 4"),
      ])
    })

  svg.g([attribute.class("sciviz-grid")], list.append(v_lines, h_lines))
}

fn render_title(plot: SciVizPlot) -> Element(msg) {
  case plot.title == "" {
    True -> svg.g([], [])
    False ->
      svg.text(
        [
          attribute.attribute("x", "16"),
          attribute.attribute("y", "24"),
          attribute.attribute("fill", plot.theme.text_color),
          attribute.attribute("font-size", "11"),
          attribute.attribute("font-weight", "bold"),
          attribute.attribute("letter-spacing", "0.08em"),
        ],
        string.uppercase(plot.title),
      )
  }
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
            attribute.attribute("points", closed_str),
            attribute.attribute("fill", fill_color),
            attribute.attribute("fill-opacity", float.to_string(opacity)),
          ])
        }
      }
    }

    GeomBar(bar_width, fill_color) -> {
      let bars =
        list.map(points, fn(p) {
          let h = plot.height -. p.y
          svg.rect([
            attribute.attribute("x", float.to_string(p.x -. { bar_width /. 2.0 })),
            attribute.attribute("y", float.to_string(p.y)),
            attribute.attribute("width", float.to_string(bar_width)),
            attribute.attribute("height", float.to_string(h)),
            attribute.attribute("fill", fill_color),
          ])
        })
      svg.g([], bars)
    }

    GeomRibbon(fill_color, opacity) -> {
      let points_str =
        points
        |> list.map(fn(p) {
          float.to_string(p.x) <> "," <> float.to_string(p.y)
        })
        |> string.join(" ")
      svg.polyline([
        attribute.attribute("points", points_str),
        attribute.attribute("fill", fill_color),
        attribute.attribute("fill-opacity", float.to_string(opacity)),
      ])
    }

    GeomPhasePortrait(vector_scale, color) -> {
      let vectors =
        list.map(points, fn(p) {
          let dx = { p.y -. { plot.height /. 2.0 } } *. 0.1 *. vector_scale
          let dy = { 0.0 -. { p.x -. { plot.width /. 2.0 } } } *. 0.1 *. vector_scale
          svg.line([
            attribute.attribute("x1", float.to_string(p.x)),
            attribute.attribute("y1", float.to_string(p.y)),
            attribute.attribute("x2", float.to_string(p.x +. dx)),
            attribute.attribute("y2", float.to_string(p.y +. dy)),
            attribute.attribute("stroke", color),
            attribute.attribute("stroke-width", "1.2"),
          ])
        })
      svg.g([], vectors)
    }

    GeomBoxplot(width, fill, stroke) -> {
      let boxes =
        list.map(points, fn(p) {
          let half_w = width /. 2.0
          svg.g([], [
            svg.rect([
              attribute.attribute("x", float.to_string(p.x -. half_w)),
              attribute.attribute("y", float.to_string(p.y -. 15.0)),
              attribute.attribute("width", float.to_string(width)),
              attribute.attribute("height", "30"),
              attribute.attribute("fill", fill),
              attribute.attribute("stroke", stroke),
              attribute.attribute("stroke-width", "1.5"),
            ]),
            svg.line([
              attribute.attribute("x1", float.to_string(p.x)),
              attribute.attribute("y1", float.to_string(p.y -. 25.0)),
              attribute.attribute("x2", float.to_string(p.x)),
              attribute.attribute("y2", float.to_string(p.y +. 25.0)),
              attribute.attribute("stroke", stroke),
              attribute.attribute("stroke-width", "1.2"),
            ]),
          ])
        })
      svg.g([], boxes)
    }

    GeomViolin(_bw, fill, opacity) -> {
      let violins =
        list.map(points, fn(p) {
          svg.circle([
            attribute.attribute("cx", float.to_string(p.x)),
            attribute.attribute("cy", float.to_string(p.y)),
            attribute.attribute("r", "18"),
            attribute.attribute("fill", fill),
            attribute.attribute("fill-opacity", float.to_string(opacity)),
          ])
        })
      svg.g([], violins)
    }

    GeomHex(radius, stroke) -> {
      let hexes =
        list.map(points, fn(p) {
          let r = radius
          let p1 = float.to_string(p.x) <> "," <> float.to_string(p.y -. r)
          let p2 = float.to_string(p.x +. r) <> "," <> float.to_string(p.y -. { r /. 2.0 })
          let p3 = float.to_string(p.x +. r) <> "," <> float.to_string(p.y +. { r /. 2.0 })
          let p4 = float.to_string(p.x) <> "," <> float.to_string(p.y +. r)
          let p5 = float.to_string(p.x -. r) <> "," <> float.to_string(p.y +. { r /. 2.0 })
          let p6 = float.to_string(p.x -. r) <> "," <> float.to_string(p.y -. { r /. 2.0 })
          let hex_pts = p1 <> " " <> p2 <> " " <> p3 <> " " <> p4 <> " " <> p5 <> " " <> p6
          svg.polygon([
            attribute.attribute("points", hex_pts),
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke", stroke),
            attribute.attribute("stroke-width", "1.5"),
          ])
        })
      svg.g([], hexes)
    }

    GeomDensity2D(_levels, color) -> {
      let densities =
        list.map(points, fn(p) {
          svg.g([], [
            svg.circle([
              attribute.attribute("cx", float.to_string(p.x)),
              attribute.attribute("cy", float.to_string(p.y)),
              attribute.attribute("r", "20"),
              attribute.attribute("fill", "none"),
              attribute.attribute("stroke", color),
              attribute.attribute("stroke-opacity", "0.4"),
            ]),
            svg.circle([
              attribute.attribute("cx", float.to_string(p.x)),
              attribute.attribute("cy", float.to_string(p.y)),
              attribute.attribute("r", "10"),
              attribute.attribute("fill", "none"),
              attribute.attribute("stroke", color),
              attribute.attribute("stroke-opacity", "0.8"),
            ]),
          ])
        })
      svg.g([], densities)
    }

    GeomErrorBar(width, stroke_w, color) -> {
      let bars =
        list.map(points, fn(p) {
          let half_w = width /. 2.0
          svg.g([], [
            svg.line([
              attribute.attribute("x1", float.to_string(p.x)),
              attribute.attribute("y1", float.to_string(p.y -. 12.0)),
              attribute.attribute("x2", float.to_string(p.x)),
              attribute.attribute("y2", float.to_string(p.y +. 12.0)),
              attribute.attribute("stroke", color),
              attribute.attribute("stroke-width", float.to_string(stroke_w)),
            ]),
            svg.line([
              attribute.attribute("x1", float.to_string(p.x -. half_w)),
              attribute.attribute("y1", float.to_string(p.y -. 12.0)),
              attribute.attribute("x2", float.to_string(p.x +. half_w)),
              attribute.attribute("y2", float.to_string(p.y -. 12.0)),
              attribute.attribute("stroke", color),
              attribute.attribute("stroke-width", float.to_string(stroke_w)),
            ]),
          ])
        })
      svg.g([], bars)
    }

    GeomStep(stroke_w, color) -> {
      let points_str =
        points
        |> list.map(fn(p) {
          float.to_string(p.x) <> "," <> float.to_string(p.y)
        })
        |> string.join(" ")
      svg.polyline([
        attribute.attribute("points", points_str),
        attribute.attribute("fill", "none"),
        attribute.attribute("stroke", color),
        attribute.attribute("stroke-width", float.to_string(stroke_w)),
      ])
    }

    GeomContour(_thresholds, color) -> {
      let contours =
        list.map(points, fn(p) {
          svg.circle([
            attribute.attribute("cx", float.to_string(p.x)),
            attribute.attribute("cy", float.to_string(p.y)),
            attribute.attribute("r", "15"),
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke", color),
          ])
        })
      svg.g([], contours)
    }

    GeomSegment(stroke_w, color) -> {
      let points_str =
        points
        |> list.map(fn(p) {
          float.to_string(p.x) <> "," <> float.to_string(p.y)
        })
        |> string.join(" ")
      svg.polyline([
        attribute.attribute("points", points_str),
        attribute.attribute("fill", "none"),
        attribute.attribute("stroke", color),
        attribute.attribute("stroke-width", float.to_string(stroke_w)),
      ])
    }

    GeomText(size, color, _font) -> {
      let texts =
        list.map(points, fn(p) {
          svg.text(
            [
              attribute.attribute("x", float.to_string(p.x)),
              attribute.attribute("y", float.to_string(p.y)),
              attribute.attribute("fill", color),
              attribute.attribute("font-size", int.to_string(size)),
            ],
            "pt",
          )
        })
      svg.g([], texts)
    }
  }
}

fn render_deck_layers(plot: SciVizPlot) -> Element(msg) {
  let layer_elements =
    list.map(plot.layers, fn(layer) {
      case layer {
        ScatterplotLayer(_id, pts, radius, color) -> {
          let circles =
            list.map(pts, fn(p) {
              let sp = dsl.project_point(plot.scale, p)
              svg.circle([
                attribute.attribute("cx", float.to_string(sp.x)),
                attribute.attribute("cy", float.to_string(sp.y)),
                attribute.attribute("r", float.to_string(radius)),
                attribute.attribute("fill", color),
              ])
            })
          svg.g([attribute.class("deck-scatterplot")], circles)
        }

        PathLayer(_id, path, stroke_width, color) -> {
          let points_str =
            path
            |> list.map(fn(p) {
              let sp = dsl.project_point(plot.scale, p)
              float.to_string(sp.x) <> "," <> float.to_string(sp.y)
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

        LineLayer(_id, lines, stroke_w, color) -> {
          let els =
            list.map(lines, fn(pair) {
              let sp1 = dsl.project_point(plot.scale, pair.0)
              let sp2 = dsl.project_point(plot.scale, pair.1)
              svg.line([
                attribute.attribute("x1", float.to_string(sp1.x)),
                attribute.attribute("y1", float.to_string(sp1.y)),
                attribute.attribute("x2", float.to_string(sp2.x)),
                attribute.attribute("y2", float.to_string(sp2.y)),
                attribute.attribute("stroke", color),
                attribute.attribute("stroke-width", float.to_string(stroke_w)),
              ])
            })
          svg.g([attribute.class("deck-lines")], els)
        }

        BitmapLayer(_id, bounds, _url, opacity) -> {
          svg.rect([
            attribute.attribute("x", float.to_string(bounds.x)),
            attribute.attribute("y", float.to_string(bounds.y)),
            attribute.attribute("width", float.to_string(bounds.width)),
            attribute.attribute("height", float.to_string(bounds.height)),
            attribute.attribute("fill", plot.theme.grid_color),
            attribute.attribute("fill-opacity", float.to_string(opacity)),
          ])
        }

        IconLayer(_id, icons, size_scale) -> {
          let els =
            list.map(icons, fn(icon) {
              let sp = dsl.project_point(plot.scale, icon.position)
              svg.circle([
                attribute.attribute("cx", float.to_string(sp.x)),
                attribute.attribute("cy", float.to_string(sp.y)),
                attribute.attribute("r", float.to_string(icon.size *. size_scale)),
                attribute.attribute("fill", icon.color),
              ])
            })
          svg.g([attribute.class("deck-icons")], els)
        }

        GeoJsonLayer(_id, features, fill, stroke) -> {
          let polys =
            list.map(features, fn(feat) {
              let pts_str =
                feat.coordinates
                |> list.map(fn(p) {
                  let sp = dsl.project_point(plot.scale, p)
                  float.to_string(sp.x) <> "," <> float.to_string(sp.y)
                })
                |> string.join(" ")
              svg.polygon([
                attribute.attribute("points", pts_str),
                attribute.attribute("fill", fill),
                attribute.attribute("stroke", stroke),
                attribute.attribute("stroke-width", "1"),
              ])
            })
          svg.g([attribute.class("deck-geojson")], polys)
        }

        GridLayer(_id, pts, cell_sz, _elev) -> {
          let cells =
            list.map(pts, fn(p) {
              let sp = dsl.project_point(plot.scale, p)
              svg.rect([
                attribute.attribute("x", float.to_string(sp.x)),
                attribute.attribute("y", float.to_string(sp.y)),
                attribute.attribute("width", float.to_string(cell_sz)),
                attribute.attribute("height", float.to_string(cell_sz)),
                attribute.attribute("fill", plot.theme.primary_color),
                attribute.attribute("fill-opacity", "0.5"),
              ])
            })
          svg.g([attribute.class("deck-grid")], cells)
        }

        HexagonLayer(_id, pts, radius, _cov) -> {
          let hexes =
            list.map(pts, fn(p) {
              let sp = dsl.project_point(plot.scale, p)
              svg.circle([
                attribute.attribute("cx", float.to_string(sp.x)),
                attribute.attribute("cy", float.to_string(sp.y)),
                attribute.attribute("r", float.to_string(radius)),
                attribute.attribute("fill", plot.theme.accent_color),
              ])
            })
          svg.g([attribute.class("deck-hexagons")], hexes)
        }

        ColumnLayer(_id, cols, _res, radius) -> {
          let els =
            list.map(cols, fn(col) {
              let sp = dsl.project_point(plot.scale, col.position)
              svg.rect([
                attribute.attribute("x", float.to_string(sp.x -. radius)),
                attribute.attribute("y", float.to_string(sp.y -. col.elevation)),
                attribute.attribute("width", float.to_string(radius *. 2.0)),
                attribute.attribute("height", float.to_string(col.elevation)),
                attribute.attribute("fill", col.color),
              ])
            })
          svg.g([attribute.class("deck-columns")], els)
        }

        PointCloudLayer(_id, pts, pt_sz, color) -> {
          let circles =
            list.map(pts, fn(p) {
              let sp = dsl.project_point(plot.scale, Point2D(p.x, p.y))
              svg.circle([
                attribute.attribute("cx", float.to_string(sp.x)),
                attribute.attribute("cy", float.to_string(sp.y)),
                attribute.attribute("r", float.to_string(pt_sz)),
                attribute.attribute("fill", color),
              ])
            })
          svg.g([attribute.class("deck-pointcloud")], circles)
        }

        ScreenGridLayer(_id, pts, cell_px) -> {
          let els =
            list.map(pts, fn(p) {
              let sp = dsl.project_point(plot.scale, p)
              svg.rect([
                attribute.attribute("x", float.to_string(sp.x)),
                attribute.attribute("y", float.to_string(sp.y)),
                attribute.attribute("width", float.to_string(cell_px)),
                attribute.attribute("height", float.to_string(cell_px)),
                attribute.attribute("fill", plot.theme.warning_color),
                attribute.attribute("fill-opacity", "0.4"),
              ])
            })
          svg.g([attribute.class("deck-screengrid")], els)
        }

        TextLayer(_id, labels, font_sz) -> {
          let els =
            list.map(labels, fn(lbl) {
              let sp = dsl.project_point(plot.scale, lbl.position)
              svg.text(
                [
                  attribute.attribute("x", float.to_string(sp.x)),
                  attribute.attribute("y", float.to_string(sp.y)),
                  attribute.attribute("fill", lbl.color),
                  attribute.attribute("font-size", int.to_string(font_sz)),
                ],
                lbl.text,
              )
            })
          svg.g([attribute.class("deck-text")], els)
        }

        TripsLayer(_id, trips, _trail_len, _cur_time) -> {
          let els =
            list.map(trips, fn(trip) {
              let pts_str =
                trip.path_with_timestamps
                |> list.map(fn(pair) {
                  let sp = dsl.project_point(plot.scale, pair.0)
                  float.to_string(sp.x) <> "," <> float.to_string(sp.y)
                })
                |> string.join(" ")
              svg.polyline([
                attribute.attribute("points", pts_str),
                attribute.attribute("fill", "none"),
                attribute.attribute("stroke", trip.color),
                attribute.attribute("stroke-width", "2"),
              ])
            })
          svg.g([attribute.class("deck-trips")], els)
        }

        H3HexagonLayer(_id, _hex_ids, _elev) -> svg.g([], [])
        S2Layer(_id, _tokens, _fill) -> svg.g([], [])
        TileLayer(_id, _tmpl, _minz, _maxz) -> svg.g([], [])
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
    VisualSprite(x, y, w, h, _tex, tint) ->
      svg.rect([
        attribute.attribute("x", float.to_string(x)),
        attribute.attribute("y", float.to_string(y)),
        attribute.attribute("width", float.to_string(w)),
        attribute.attribute("height", float.to_string(h)),
        attribute.attribute("fill", tint),
      ])
    VisualNineSlicePlane(x, y, w, h, _l, _t, _r, _b, fill) ->
      svg.rect([
        attribute.attribute("x", float.to_string(x)),
        attribute.attribute("y", float.to_string(y)),
        attribute.attribute("width", float.to_string(w)),
        attribute.attribute("height", float.to_string(h)),
        attribute.attribute("fill", fill),
        attribute.attribute("stroke", "#38bdf8"),
        attribute.attribute("stroke-width", "2"),
      ])
    VisualTilingSprite(x, y, w, h, _sx, _sy, _pat) ->
      svg.rect([
        attribute.attribute("x", float.to_string(x)),
        attribute.attribute("y", float.to_string(y)),
        attribute.attribute("width", float.to_string(w)),
        attribute.attribute("height", float.to_string(h)),
        attribute.attribute("fill", "#1e293b"),
      ])
    VisualParticleContainer(particles, _blend) -> {
      let circles =
        list.map(particles, fn(p) {
          svg.circle([
            attribute.attribute("cx", float.to_string(p.x)),
            attribute.attribute("cy", float.to_string(p.y)),
            attribute.attribute("r", float.to_string(p.scale *. 2.0)),
            attribute.attribute("fill", p.color),
            attribute.attribute("fill-opacity", float.to_string(p.alpha)),
          ])
        })
      svg.g([], circles)
    }
    VisualMesh(vertices, _uvs, _indices, color) -> {
      let pts_str =
        vertices
        |> list.map(fn(p) {
          float.to_string(p.x) <> "," <> float.to_string(p.y)
        })
        |> string.join(" ")
      svg.polygon([
        attribute.attribute("points", pts_str),
        attribute.attribute("fill", color),
        attribute.attribute("stroke", "#0284c7"),
      ])
    }
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
