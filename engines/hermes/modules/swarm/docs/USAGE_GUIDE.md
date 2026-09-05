# Swarm Module Usage Guide (Agents & Users)

This guide documents the procedures for interacting with the `modules/swarm` multi-agent execution engine through the Declarative Intent Configuration surface.

## 1. For Users

### Defining Declarative Intent
As a user, you do not write OCaml scripts to trigger the swarm. You define **Declarative Intent**. This tells the swarm *what* your objective is, and the underlying path synthesis engine determines *how* to achieve it.

1. **Create an Intent File (`intent.yaml`)**:
   ```yaml
   intent:
     target: "Migrate database schema to support temporal tables"
     constraints:
       - parallelism: "max"
       - integrity: "benchmark"
     capabilities:
       - "database_design"
       - "formal_verification"
     success_criteria:
       - "Migration passes dune tests"
       - "Zero data loss detected in replay tests"
   ```

2. **Execute via Swarm CLI**:
   Pass your intent to the swarm engine. The CLI parses your file, passes it to `intent_config.ml`, and automatically triggers `sop_execution.ml`.
   ```bash
   # Make sure you are in the correct OCaml switch
   eval $(opam env --switch=/home/an/dev/ver/zigvm --set-switch)

   # Run the swarm
   dune exec modules/swarm/bin/swarm_cli.exe -- apply intent.yaml
   ```

3. **Monitor the Fractal Telemetry**:
   To view the live decisions the agents are making, request the fractal telemetry dashboard:
   ```bash
   dune exec modules/swarm/bin/swarm_cli.exe -- report telemetry
   ```

---

## 2. For Agents

When an autonomous agent (like yourself) is tasked with operating the Swarm, adhere to the following MBASE protocol:

### Step 1. Parse the Original Directive
Instead of manually editing source code to solve a problem, use the `intent_config.ml` surface. Synthesize the user's objective into an `intent.yaml` (or pass it directly through OCaml types if you are operating internally).

### Step 2. Trigger the Autonomous Synthesis Engine
Pass the configuration to `Swarm_intent.synthesize_dag`. 
- The engine will automatically break the intent down into a Directed Acyclic Graph (DAG).
- It will automatically allocate those DAG tasks across `Agent_1` (System Architect) through `Agent_5` (Resource Auditor) defined in `swarm_ontology.ml`.

### Step 3. Observe and Audit (Phase 5)
Agents should **never** skip formal verification. Once the swarm executes, you must verify its output.
1. Run the swarm test suites:
   ```bash
   dune runtest modules/swarm/
   ```
2. Check the `telemetry_node` digests emitted by the swarm to ensure there were no CRDT merge conflicts in the `swarm_algebra.ml` layer.

### Step 4. Hand-off (Phase 6)
If the DAG completes and the success criteria defined in the intent are met, the swarm run is successful. Report the final telemetry dashboard to the user.

## 3. Pure OCaml Combinator API

If you are invoking the Swarm programmatically from within another OCaml service instead of via YAML, use the pure OCaml Combinator API provided by `swarm_api.ml`:

```ocaml
open Swarm_api

let run_swarm () =
  let my_intent = 
    make_intent "Refactor database schema"
    |> with_constraint "parallelism" "max"
    |> with_constraint "integrity" "benchmark"
    |> requiring_capability "database_design"
    |> requiring_success_criterion "0 dune test failures"
    |> requiring_intelligence Fast_OODA
    |> requiring_intelligence Raven
    |> requiring_intelligence Rete_UL
  in
  let dag = Intent_config.synthesize_dag my_intent in
  (* Pass the synthesized dag to sop_execution for Domain parallel processing *)
  run_dag_somehow dag
```
This guarantees compile-time safety and prevents invalid intents from ever reaching the synthesis engine. 

### Leveraging Machine IQ (MIQ)
The `requiring_intelligence` combinator dynamically routes the task execution DAG through advanced cybernetic and cognitive modules, significantly increasing the swarm's operational IQ:
- **Fast_OODA**: Triggers the Observe-Orient-Decide-Act cybernetic loop.
- **Raven**: Applies abstract reasoning for complex non-linear problem solving.
- **Rete_UL / STPA / STAN**: Triggers Expert Systems, Safety Constraint Analysis, and Bayesian Inference algorithms.

## 4. Agentic Memory and KM (Wiki/ZK) Data Integration

The Swarm Engine automatically provisions a 4-tier autonomous memory architecture upon startup:
1. **Working Memory**: Active fiber state across the 5 OCaml domains.
2. **Episodic Memory**: A cryptographically hashed log of all events.
3. **Semantic Memory**: The core Knowledge Graph of objective truths.
4. **Procedural Memory**: Cached, optimized execution DAGs.

### Knowledge Management (RAG & Publishing)
The Swarm is natively bound to the Hermes Wiki and ZK system data through `swarm_km.ml`. 
- **Retrieval**: Before synthesis begins, the Swarm queries the ZK system to pull contextual failures, guidelines, and historical data into its working memory.
- **Publishing**: Upon successful convergence of an Intent, the Swarm autonomously publishes its newly synthesized Semantic Facts out to the ZK system as structured Notes (e.g. `zk://hermes_wiki/fact_[hash]`).
