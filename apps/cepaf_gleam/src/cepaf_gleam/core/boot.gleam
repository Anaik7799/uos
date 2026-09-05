//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/core/boot</module>
////     <fsharp-lineage>Cepaf.Core.BootSequence.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>5-Stage Transactional Boot Sequence</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-MESH-003</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       F# `Result.bind` ≅ Gleam `use` for monadic short-circuiting.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import gleam/list

pub type BootStage {
  Stage1InitializeSystem
  Stage2LoadConfiguration
  Stage3MountFilesystems
  Stage4StartServices
  Stage5ActivateApplication
}

pub type BootState {
  BootState(current_stage: BootStage, completed_stages: List(BootStage))
}

pub type BootError {
  BootError(stage: BootStage, reason: String)
}

pub fn start_boot() -> BootState {
  BootState(current_stage: Stage1InitializeSystem, completed_stages: [])
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> System is halted. </P>
///     <C> execute_stage(state, action) </C>
///     <Q> Returns the sequentially incremented BootState, or halts boot on Error. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn execute_stage(
  state: BootState,
  action: fn(BootState) -> Result(BootState, BootError),
) -> Result(BootState, BootError) {
  case action(state) {
    Ok(next_state) -> {
      let completed = [state.current_stage, ..next_state.completed_stages]
      let next_stage = case state.current_stage {
        Stage1InitializeSystem -> Stage2LoadConfiguration
        Stage2LoadConfiguration -> Stage3MountFilesystems
        Stage3MountFilesystems -> Stage4StartServices
        Stage4StartServices -> Stage5ActivateApplication
        Stage5ActivateApplication -> Stage5ActivateApplication
      }
      Ok(BootState(current_stage: next_stage, completed_stages: completed))
    }
    Error(err) -> Error(err)
  }
}

pub fn run_full_sequence(
  initial: BootState,
  actions: List(fn(BootState) -> Result(BootState, BootError)),
) -> Result(BootState, BootError) {
  list.try_fold(actions, initial, execute_stage)
}
