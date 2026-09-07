#mod_use "product_workflow_core.ml";;
open Product_workflow_core
let count=ref 0
let check name p = if not p then failwith name else (incr count; Printf.printf "ok %s\n" name)
let binding={candidate="candidate";specification="spec";oracle="oracle";executable="exe";normalizer="norm";checker="checker"}
let receipt kind sequence = {case_id="case";kind;binding;sequence;observed=10.;expires=20.;passed=true;artifact_valid=true;invocation_valid=true}
let runtime=receipt Runtime 1 and formal=receipt Formal 2
let eval ?(now=15.) ?(current=true) ?(expected=binding) xs = evaluate_case ~now ~source_current:current ~expected ~case_id:"case" xs
let n id parent level required = {id;parent;level;required}
let nodes=[n "p" None Product true;n "f" (Some "p") Feature true;n "r" (Some "f") Requirement true;n "a" (Some "r") Acceptance true]
let () =
 check "complete containment is valid" (validate_nodes nodes=Ok ());
 List.iter (fun (label,ns) -> check label (Result.is_error (validate_nodes ns)))
  ["empty tree rejected",[];"duplicate IDs rejected",nodes@[List.hd nodes];
   "missing parent rejected",List.tl nodes;"skipped level rejected",[List.hd nodes;n "a" (Some "p") Acceptance true];
   "empty required root rejected",[List.hd nodes];"cycle rejected",[n "p" (Some "a") Product true;n "a" (Some "p") Acceptance true]];
 check "empty receipt set is UNRUN" ((eval []).state=Unrun);
 check "runtime alone cannot pass" ((eval [runtime]).state=Unrun);
 check "formal alone cannot pass" ((eval [formal]).state=Unrun);
 check "two exact fresh receipts pass" ((eval [runtime;formal]).state=Passed);
 check "expiry boundary is stale" ((eval ~now:20. [runtime;formal]).state=Stale);
 check "source changes invalidate credit" ((eval ~current:false [runtime;formal]).state=Stale);
 List.iter (fun (name,b) -> check name ((eval [{runtime with binding=b};formal]).state=Stale))
  ["candidate mismatch",{binding with candidate="different"};"spec mismatch",{binding with specification="different"};
   "oracle mismatch",{binding with oracle="different"};"executable mismatch",{binding with executable="different"};
   "normalizer mismatch",{binding with normalizer="different"};"checker mismatch",{binding with checker="different"}];
 check "empty expected identity blocked" ((eval ~expected:{binding with checker=""} [runtime;formal]).state=Blocked);
 check "future receipt blocked" ((eval [{runtime with observed=16.};formal]).state=Blocked);
 check "nonfinite time blocked" ((eval ~now:nan [runtime;formal]).state=Blocked);
 check "artifact tamper blocked" ((eval [{runtime with artifact_valid=false};formal]).state=Blocked);
 check "invalid invocation blocked" ((eval [{runtime with invocation_valid=false};formal]).state=Blocked);
 check "latest failure overrides older pass" ((eval [runtime;formal;{runtime with sequence=3;passed=false}]).state=Failed);
 check "mismatched latest receipt cannot expose older pass" ((eval [runtime;formal;{runtime with sequence=3;binding={binding with candidate="old"}}]).state=Stale);
 check "duplicate latest sequence blocked" ((eval [runtime;runtime;formal]).state=Blocked);
 check "another case cannot supply evidence" ((eval [{runtime with case_id="other"};formal]).state=Unrun);
 check "empty fold cannot pass" ((roll_up []).state=Unrun);
 check "required failure propagates" ((roll_up [eval [runtime;formal];eval [{runtime with passed=false};formal]]).state=Failed);
 check "missing required child propagates" ((roll_up [eval [runtime;formal];eval []]).state=Unrun);
 for mask=0 to 511 do
  let bits=List.init 9 (fun bit -> mask land (1 lsl bit) <> 0) in
  if eligible_bits bits <> (mask=511) then failwith "finite eligibility counterexample"
 done;
 check "all 512 eligibility vectors match independent truth table" true;
 check "wrong arity rejected" (not (eligible_bits []) && not (eligible_bits (List.init 10 (fun _ -> true))));
 Printf.printf "product-workflow core tests: %d passed\n" !count
