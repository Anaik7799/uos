type sovereign_id = AGY | Claude | Codex | OpenRouter

type cycle_record = {
  cycle_num : int;
  ev_tag : string;
  title : string;
  target_aspects : int list;
  target_layer : int;
  expected_gain_pct : float;
  risk_score : float;
}

type quorum_ballot = {
  cycle_num : int;
  approvals : sovereign_id list;
  rejections : sovereign_id list;
  is_ratified : bool;
}

type cycle_receipt = {
  cycle_num : int;
  ev_tag : string;
  generation : int;
  lyapunov_energy_prior : float;
  lyapunov_energy_posterior : float;
  receipt_sha256 : string;
}

let all_15_cycles () : cycle_record list = [
  { cycle_num = 1; ev_tag = "EV-111"; title = "Substrate & HW Armor"; target_aspects = [1; 3]; target_layer = 0; expected_gain_pct = 18.0; risk_score = 0.04 };
  { cycle_num = 2; ev_tag = "EV-112"; title = "Standalone Jujutsu Monorepo"; target_aspects = [2]; target_layer = 9; expected_gain_pct = 15.0; risk_score = 0.03 };
  { cycle_num = 3; ev_tag = "EV-113"; title = "Deterministic ZigVM & VFS"; target_aspects = [5]; target_layer = 1; expected_gain_pct = 22.0; risk_score = 0.02 };
  { cycle_num = 4; ev_tag = "EV-114"; title = "OTP 29 Supervision & Homeostasis"; target_aspects = [4; 8]; target_layer = 2; expected_gain_pct = 20.0; risk_score = 0.03 };
  { cycle_num = 5; ev_tag = "EV-115"; title = "Sa-Plan Durable Workflows"; target_aspects = [17]; target_layer = 3; expected_gain_pct = 24.0; risk_score = 0.02 };
  { cycle_num = 6; ev_tag = "EV-116"; title = "Quarantined MAX/Mojo SIMD Ranker"; target_aspects = [9]; target_layer = 4; expected_gain_pct = 26.0; risk_score = 0.03 };
  { cycle_num = 7; ev_tag = "EV-117"; title = "Zenoh Fractal Mesh Backplane"; target_aspects = [10]; target_layer = 4; expected_gain_pct = 28.0; risk_score = 0.02 };
  { cycle_num = 8; ev_tag = "EV-118"; title = "POODAVR 7-Stage Cybernetic Loop"; target_aspects = [4; 8]; target_layer = 5; expected_gain_pct = 25.0; risk_score = 0.03 };
  { cycle_num = 9; ev_tag = "EV-119"; title = "NASA JPL F Prime (F') Statecharts"; target_aspects = [1; 4]; target_layer = 5; expected_gain_pct = 17.0; risk_score = 0.01 };
  { cycle_num = 10; ev_tag = "EV-120"; title = "AG-UI 32-Event Stream Protocol"; target_aspects = [11]; target_layer = 6; expected_gain_pct = 19.0; risk_score = 0.02 };
  { cycle_num = 11; ev_tag = "EV-121"; title = "A2UI Declarative Component Catalog"; target_aspects = [12]; target_layer = 6; expected_gain_pct = 21.0; risk_score = 0.02 };
  { cycle_num = 12; ev_tag = "EV-122"; title = "Penta-Stack Multi-Interface Parity"; target_aspects = [13]; target_layer = 6; expected_gain_pct = 23.0; risk_score = 0.02 };
  { cycle_num = 13; ev_tag = "EV-123"; title = "Universal Tailscale FQDN Routing"; target_aspects = [14]; target_layer = 7; expected_gain_pct = 16.0; risk_score = 0.01 };
  { cycle_num = 14; ev_tag = "EV-124"; title = "Knowledge Management Triad"; target_aspects = [16]; target_layer = 7; expected_gain_pct = 22.0; risk_score = 0.02 };
  { cycle_num = 15; ev_tag = "EV-125"; title = "Formal Verification & Sovereign Seal"; target_aspects = [6; 7; 15]; target_layer = 8; expected_gain_pct = 30.0; risk_score = 0.01 };
]

let is_aspect_covered (aspect_id : int) (cycles : cycle_record list) : bool =
  List.exists (fun c -> List.mem aspect_id c.target_aspects) cycles

let verify_full_17_aspect_completeness (cycles : cycle_record list) : bool =
  let rec check_aspects i =
    if i > 17 then true
    else if is_aspect_covered i cycles then check_aspects (i + 1)
    else false
  in
  check_aspects 1

let ratify_cycle (ballot : quorum_ballot) : bool =
  List.length ballot.approvals >= 3

let apply_evolution_step (current_gen : int) (current_energy : float) (cycle : cycle_record) : cycle_receipt =
  let next_gen = current_gen + 1 in
  let next_energy = current_energy *. 0.7 in
  let raw_receipt = Printf.sprintf "cycle:%d:gen:%d:tag:%s" cycle.cycle_num next_gen cycle.ev_tag in
  let sha256_mock = "sha256-" ^ raw_receipt in
  {
    cycle_num = cycle.cycle_num;
    ev_tag = cycle.ev_tag;
    generation = next_gen;
    lyapunov_energy_prior = current_energy;
    lyapunov_energy_posterior = next_energy;
    receipt_sha256 = sha256_mock;
  }
