let require name condition =
  if not condition then failwith ("FAILED: " ^ name)

let sample s logical writer payload =
  Ev98_health_model.{ sample = s; logical; writer; payload }

let () =
  let newer = sample 2 0 0 0 in
  let older_logically_later = sample 1 2 2 1 in
  require "sample time dominates logical version"
    (Ev98_health_model.select newer older_logically_later = newer);
  let a = sample 1 1 0 0 in
  let b = sample 1 1 2 1 in
  require "writer resolves same sample and logical version"
    (Ev98_health_model.select a b = b);
  require "well formed equal key requires equal payload"
    (not (Ev98_health_model.well_formed_pair (sample 1 1 1 0) (sample 1 1 1 1)));
  require "raw association-list order is not structural commutativity"
    (Ev98_health_model.raw_list_order_counterexample ());
  require "finite independent reference laws hold"
    (Ev98_health_model.laws_hold_by_enumeration ());
  print_endline "PASS EV98 independent health-order reference controls"
