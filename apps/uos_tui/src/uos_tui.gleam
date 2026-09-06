//// Package entry: `gleam run` launches the reference cockpit on the live driver;
//// `gleam run -- snapshot` prints one 120x40 frame as plain text (for headless callers);
//// `gleam run -- dictionary` prints the F´ ground dictionary JSON.

import argv
import gleam/io
import uos_tui/cockpit
import uos_tui/fprime
import uos_tui/geometry.{Size}
import uos_tui/live

pub fn main() -> Nil {
  let model = cockpit.init_model(live.utc_now(), "working-copy")
  case argv.load().arguments {
    ["snapshot"] ->
      io.println(live.snapshot_text(cockpit.app(model), Size(120, 40)))
    ["dictionary"] -> io.println(fprime.dictionary_string())
    _ -> {
      let _ = live.run(cockpit.app(model), live.default_options)
      Nil
    }
  }
}
