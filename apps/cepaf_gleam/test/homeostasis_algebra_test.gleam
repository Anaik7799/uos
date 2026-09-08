import cepaf_gleam/ha/homeostasis_evolution_engine as engine
import cepaf_gleam/ui/homeostasis_data as data
import cepaf_gleam/ui/homeostasis_status as status
import cepaf_gleam/ui/lustre/homeostasis_evolution_hud as hud
import cepaf_gleam/ui/tui/homeostasis_evolution_view as tui
import gleam/list
import gleam/string
import gleam/option.{Some}
import gleeunit/should
import lustre/element

pub fn thirty_model_evolutions_preserve_generation_and_history_test() {
  let state = data.cycles(30) |> list.fold(engine.init_homeostasis_system(0),fn(s,n){
    let assert Ok(next) = data.evolve_model(s,n)
    next.generation |> should.equal(n)
    list.length(next.ratified_evolutions) |> should.equal(n)
    { next.metrics.timestamp_us > s.metrics.timestamp_us } |> should.be_true()
    { next.metrics.lyapunov_v >=. 0.0 } |> should.be_true()
    { next.metrics.lyapunov_v == 0.5 *. next.metrics.error *. next.metrics.error } |> should.be_true()
    next
  })
  state.generation |> should.equal(30)
}

pub fn thirty_cycles_all_modes_and_scenarios_share_denotation_test() {
  data.cycles(30) |> list.each(fn(cycle){
    [data.Nominal,data.Disturbance,data.Recovery,data.MissingSource] |> list.each(fn(scenario){
      let selection = data.Selection(data.TestData,scenario,cycle)
      let #(snapshot,now) = data.read(selection)
      let fields = status.fields(snapshot,now)
      let gui = hud.render_view(selection,"all",snapshot,now) |> element.to_string()
      let terminal = tui.render_snapshot(snapshot,now,240,100)
      let api = status.to_json(snapshot,now)
      fields |> list.each(fn(field){
        string.contains(gui,"value-" <> field.0) |> should.be_true()
        string.contains(terminal,tui.safe_text(field.1 <> ": " <> field.2)) |> should.be_true()
        string.contains(api,field.0) |> should.be_true()
      })
      status.status(snapshot,now) |> should.equal(case scenario { data.MissingSource -> status.Unavailable _ -> status.Simulated })
      let #(repeat,_) = data.read(selection)
      status.fields(repeat,now) |> should.equal(fields)
    })
  })
}

pub fn real_mode_observes_vm_without_inventing_homeostasis_test() {
  let #(snapshot,now) = data.read(data.default())
  status.status(snapshot,now) |> should.equal(status.Observed)
  let assert Some(metrics) = status.runtime_metrics(snapshot)
  { metrics.process_count > 0 } |> should.be_true()
  { metrics.scheduler_count > 0 } |> should.be_true()
  status.to_json(snapshot,now) |> string.contains("\"metrics\":null") |> should.be_true()
  status.to_json(snapshot,now) |> string.contains("\"control_authority\":\"none\"") |> should.be_true()
}

pub fn invalid_mode_and_cycle_cannot_select_real_execution_test() {
  data.parse([#("mode","live-admin")]) |> should.be_error()
  data.parse([#("mode","test"),#("cycle","31")]) |> should.be_error()
  data.parse([#("mode","test"),#("cycle","0")]) |> should.be_error()
}

pub fn threshold_preview_is_monotone_and_has_no_real_authority_test() {
  let selection = data.Selection(data.TestData,data.Nominal,1)
  data.review(selection,0.2,0.3) |> should.equal(Ok(data.Preview(False)))
  data.review(selection,0.35,0.45) |> should.equal(Ok(data.Preview(True)))
  data.review(selection,1.0,1.0) |> should.equal(Ok(data.Preview(True)))
  data.review(selection,-0.01,1.0) |> should.be_error()
  data.review(selection,1.01,1.0) |> should.be_error()
  data.cycles(30) |> list.each(fn(_){
    data.review(data.default(),1.0,1.0) |> should.equal(Ok(data.DeniedNoAuthority))
  })
}
