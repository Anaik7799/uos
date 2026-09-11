//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX COGNITIVE OTP SUPERVISOR
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/cortex/cortex_sup</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Cortex OODA & Hedged Cascade Supervisor</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-COG-MAX-001, SC-SUP-001, SC-JIDOKA-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/cortex/ooda_actor
import gleam/otp/actor
import gleam/otp/static_supervisor as sup
import gleam/otp/supervision

pub type ChildSpec {
  ChildSpec(id: String, description: String, fractal_layer: String)
}

pub type CortexSupervisorSpec {
  CortexSupervisorSpec(
    name: String,
    intensity: Int,
    period_seconds: Int,
    children: List(ChildSpec),
  )
}

pub fn spec() -> CortexSupervisorSpec {
  CortexSupervisorSpec(
    name: "CortexSupervisor",
    intensity: 3,
    period_seconds: 60,
    children: [
      ChildSpec(
        id: "CortexOodaActor",
        description: "4-Phase OODA convergence loop with Jidoka Andon Stop Line",
        fractal_layer: "L5_COGNITIVE",
      ),
    ],
  )
}

pub fn start() -> Result(actor.Started(sup.Supervisor), actor.StartError) {
  sup.new(sup.OneForOne)
  |> sup.restart_tolerance(intensity: 3, period: 60)
  |> sup.add(ooda_actor.supervised("uos-cortex-ooda-1"))
  |> sup.start
}

pub fn supervised() -> supervision.ChildSpecification(sup.Supervisor) {
  supervision.supervisor(fn() { start() })
}
