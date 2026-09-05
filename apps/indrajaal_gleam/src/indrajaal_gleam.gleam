import gleam/io
import gleam/option.{None}
import indrajaal/holon

pub fn main() {
  let h = holon.new_holon("root-holon", None)
  io.println("Indrajaal Holon Runtime active: " <> h.coord.id)
}
