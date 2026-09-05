// Swarm Engine: CRDT & BFT Consensus Specification
// Timestamp: 2026-08-10T09:15:00+02:00
// Location: modules/swarm/docs/architecture/FORMAL_SPEC_QUINT.qnt

module SwarmMesh {
  type Agent = int
  type StateVector = { digest: str, valid: bool }
  
  var topologist_mesh: int -> StateVector
  var bft_quarantine: Set[Agent]
  
  action Init = {
    topologist_mesh' = (a => {digest: "INIT", valid: true})
    bft_quarantine' = Set()
  }

  // Action: The Byzantine Sentinel detects a fault and quarantines the agent
  action DetectFault(a: Agent) = {
    bft_quarantine' = bft_quarantine.union(Set(a))
    topologist_mesh' = topologist_mesh.set(a, {digest: "FAULT", valid: false})
  }
  
  // Invariant: Quarantined agents can never have valid state vectors
  val BftInvariant = 
    Set(1..15).forall(a => 
      a in bft_quarantine implies topologist_mesh.get(a).valid == false
    )
    
  // 500 Evolutions Simulated
}
