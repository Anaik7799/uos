// Stateless projection model. HTTP/MCP implementation conformance is tested separately.
// #fractal-l0 #fractal-l5 #fractal-l8 #zk-adr #zero-muda
module km_triad_mcp_brain_memory {
  var disk: int
  var present: bool
  var canonical: bool
  var allowlisted: bool
  var symlink: bool
  var nlinks: int
  var worker: bool
  var served: int
  var status: int
  var reads: int
  var writes: int
  var deletes: int
  var restarts: int
  var stage: int
  var surface: str

  val safe = allowlisted and not(symlink) and nlinks <= 1
  def code(ok: bool, present: bool): int = if (not(ok)) 403 else if (present) 200 else 404
  action init = all {
    disk' = 0, present' = false, canonical' = true,
    allowlisted' = true, symlink' = false, nlinks' = 1, worker' = true,
    served' = 0, status' = 404, reads' = 0, writes' = 0, deletes' = 0,
    restarts' = 0, stage' = 0, surface' = "http"
  }
  // Create/Modify are visible at the next call with no clock tick or cache refresh.
  action createOrModify = all {
    disk' = disk + 1, present' = true, writes' = writes + 1,
    served' = 0, status' = 0,
    canonical' = canonical, allowlisted' = allowlisted, symlink' = symlink,
    nlinks' = nlinks, worker' = worker, reads' = reads, deletes' = deletes,
    restarts' = restarts, stage' = stage, surface' = surface
  }
  action delete = all {
    present' = false, deletes' = deletes + 1, status' = 0, served' = 0,
    disk' = disk, canonical' = canonical, allowlisted' = allowlisted,
    symlink' = symlink, nlinks' = nlinks, worker' = worker, reads' = reads,
    writes' = writes, restarts' = restarts, stage' = stage, surface' = surface
  }
  action read = {
    nondet s = oneOf(Set("http", "sw_network_bypass", "read_file", "knowledge_search", "zk_transclude", "resources/read"))
    all {
      status' = if (canonical) code(safe, present) else 503,
      served' = if (canonical and safe and present) disk else 0,
      reads' = reads + 1, stage' = (stage + 1) % 7, surface' = s,
      disk' = disk, present' = present, canonical' = canonical,
      allowlisted' = allowlisted, symlink' = symlink, nlinks' = nlinks,
      worker' = worker, writes' = writes, deletes' = deletes, restarts' = restarts
    }
  }
  action boundaryChange = {
    nondet a = oneOf(Set(true, false))
    nondet l = oneOf(Set(true, false))
    nondet n = oneOf(Set(1, 2))
    nondet c = oneOf(Set(true, false))
    all {
      allowlisted' = a, symlink' = l, nlinks' = n, canonical' = c,
      status' = 0, served' = 0, disk' = disk, present' = present,
      worker' = worker, reads' = reads, writes' = writes, deletes' = deletes,
      restarts' = restarts, stage' = stage, surface' = surface
    }
  }
  action restart = all {
    worker' = not(worker), restarts' = restarts + 1, status' = 0, served' = 0,
    disk' = disk, present' = present, canonical' = canonical,
    allowlisted' = allowlisted, symlink' = symlink, nlinks' = nlinks,
    reads' = reads, writes' = writes, deletes' = deletes, stage' = stage, surface' = surface
  }
  action step = any { createOrModify, delete, read, boundaryChange, restart }
  val always_fresh_and_quarantined_inv = all {
    status == 200 implies (served == disk and present and safe and canonical),
    status != 0 and not(canonical) implies status == 503,
    status != 0 and canonical and not(safe) implies status == 403,
    status != 0 and canonical and safe and not(present) implies status == 404,
    stage >= 0 and stage < 7
  }
  // Deliberately false invariant: a counterexample is the non-vacuity witness.
  val non_vacuity_witness_inv = not(reads > 0 and writes > 0 and status == 200)
}
