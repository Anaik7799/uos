import gleam/list
import gleam/string
import gleeunit/should
import uos_tui/aspects
import uos_tui/fprime

pub fn component_is_active_and_named_test() {
  let c = fprime.component()
  c.comp_name |> should.equal("UosTui")
  c.kind |> should.equal(fprime.Active)
}

pub fn dictionary_validates_test() {
  fprime.validate(fprime.component(), fprime.instance())
  |> should.equal(Ok(Nil))
}

pub fn base_id_outside_agent_window_test() {
  let inst = fprime.instance()
  { inst.base_id < 0x1000 || inst.base_id >= 0x1400 } |> should.be_true
  fprime.validate(fprime.component(), fprime.Instance(..inst, base_id: 0x1040))
  |> should.equal(Error("ground component inside agent DMC window"))
}

pub fn duplicate_opcode_rejected_test() {
  let c = fprime.component()
  let dup =
    fprime.Component(
      ..c,
      commands: list.append(c.commands, [
        fprime.Command("DUP", 0x01, fprime.SyncCmd, []),
      ]),
    )
  fprime.validate(dup, fprime.instance())
  |> should.equal(Error("duplicate command opcode"))
}

pub fn engine_ports_declared_for_aspects_test() {
  let names = fprime.port_names(fprime.component())
  list.each(fprime.engine_ports, fn(p) {
    list.contains(names, p) |> should.be_true
  })
  list.contains(names, "intent_out") |> should.be_true
}

pub fn dictionary_json_shape_test() {
  let j = fprime.dictionary_string()
  list.each(
    [
      "\"commands\"",
      "\"events\"",
      "\"telemetryChannels\"",
      "\"parameters\"",
      "\"ports\"",
      "\"uosTui.TUI_REQUEST_INTENT\"",
      "\"uosTui.FrameMicros\"",
      aspects.os_nvme_serial,
    ],
    fn(needle) { string.contains(j, needle) |> should.be_true },
  )
}

pub fn absolute_opcodes_are_offset_by_base_test() {
  fprime.dictionary_string()
  |> string.contains("\"opcode\":" <> string.inspect(0x2000 + 0x05))
  |> should.be_true
}

pub fn channels_cover_telemetry_context_test() {
  let names = fprime.channel_names(fprime.component())
  list.each(["FrameCount", "FrameMicros", "ScreenDepth", "CockpitMode"], fn(n) {
    list.contains(names, n) |> should.be_true
  })
}
