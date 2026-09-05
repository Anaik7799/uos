(* SysML Ontology and FPP Algebra for the LM Studio Dashboard 
 * Focus: Local Hardware Constraints, Computational Efficiency, Data Privacy
 *)

type dashboard_archetype =
  | Infrastructure_View   (* For DevOps/SysAdmins: Keep servers alive *)
  | Inference_UX_View     (* For Product Owners: Serve users fast & accurately *)
  | Training_MLOps_View   (* For Data Scientists: Eval runs & degradation *)

type metric_type =
  | Gauge
  | Counter
  | Heatmap
  | TimeSeries

type dashboard_kpi = {
  id : string;
  archetype : dashboard_archetype;
  metric : metric_type;
  description : string;
}

let define_infrastructure_kpis () = [
  { id = "vram_utilization_pct"; archetype = Infrastructure_View; metric = Gauge; 
    description = "Amount of GPU memory used. Out of VRAM triggers a crash." };
  { id = "gpu_compute_utilization_pct"; archetype = Infrastructure_View; metric = Gauge; 
    description = "Percentage of time GPU kernels are active." };
  { id = "system_memory_swap_gb"; archetype = Infrastructure_View; metric = Gauge; 
    description = "RAM usage, critical for CPU offloading." };
  { id = "power_draw_watts"; archetype = Infrastructure_View; metric = TimeSeries; 
    description = "Thermal tracking to prevent degradation." };
  { id = "disk_io_speeds"; archetype = Infrastructure_View; metric = TimeSeries; 
    description = "Monitor model weight loading times." }
]

let define_inference_ux_kpis () = [
  { id = "time_to_first_token_ms"; archetype = Inference_UX_View; metric = Gauge; 
    description = "TTFT: Time before generation begins (pre-fill phase)." };
  { id = "time_per_output_token_ms"; archetype = Inference_UX_View; metric = Gauge; 
    description = "TPOT: Time spent generating each token." };
  { id = "tokens_per_second"; archetype = Inference_UX_View; metric = Gauge; 
    description = "TPS: Generation throughput." };
  { id = "queue_wait_time"; archetype = Inference_UX_View; metric = TimeSeries; 
    description = "Wait time before LM Studio processes the request." };
  { id = "context_window_usage"; archetype = Inference_UX_View; metric = Heatmap; 
    description = "How close users are getting to the 8192/128k token limit." };
  { id = "data_leakage_audit"; archetype = Inference_UX_View; metric = Counter; 
    description = "Count of inputs flagged by Llama Guard blocking corporate data egress." }
]

let define_mlops_kpis () = [
  { id = "perplexity_drift"; archetype = Training_MLOps_View; metric = TimeSeries; 
    description = "PPL drift indicating local model degradation." };
  { id = "quantization_degeneration"; archetype = Training_MLOps_View; metric = Gauge; 
    description = "Comparison of 4-bit Q4_K_M vs FP16 baseline scores." }
]

let get_all_kpis () = 
  define_infrastructure_kpis () @ define_inference_ux_kpis () @ define_mlops_kpis ()
