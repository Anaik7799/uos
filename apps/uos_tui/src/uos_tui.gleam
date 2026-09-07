//// Package entry. `gleam run -- <command>`:
////   (none)                      live gallery demo (raw mode, alt screen, q quits)
////   snapshot                    one 120x40 gallery frame as text
////   dictionary                  F´ ground dictionary JSON
////   features | features-json    feature sheet generated from code

import argv
import gleam/io
import gleam/json
import uos_tui/features
import uos_tui/fprime
import uos_tui/gallery
import uos_tui/geometry.{Size}
import uos_tui/live

pub fn main() -> Nil {
  let model = gallery.init_model(live.utc_now(), "working-copy")
  case argv.load().arguments {
    ["snapshot"] ->
      io.println(live.snapshot_text(gallery.app(model), Size(120, 40)))
    ["dictionary"] -> io.println(fprime.dictionary_string())
    ["features"] -> io.println(features.to_markdown(features.sheet([])))
    ["features-json"] ->
      io.println(json.to_string(features.to_json(features.sheet([]))))
    _ -> {
      let _ = live.run(gallery.app(model), live.default_options)
      Nil
    }
  }
}
