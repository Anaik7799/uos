# SOP: Swarm Invocation and Scale

## 1. Purpose
This Standard Operating Procedure strictly defines how automated execution engines (like the Autonomous Compilation Engine or multi-agent coordinators) must invoke the Swarm Engine to handle parallel execution and complex DAG synthesis.

## 2. Constraints & Mandates
- **Pure OCaml Only**: Scripts must use the `swarm_api.ml` OCaml interface. External framework logic (ADK, Python, JS) is explicitly blocked at the boundary.
- **ASSP Compliance**: Any node execution within the swarm must synchronize state via the Active State Synchronization Protocol (ASSP) before reading/writing persistent files.
- **Fractal Scaling**: The Swarm defaults to 5 static Core Council agents. It is strictly forbidden to manually override the `$N$` or `$M$` scale bounds; the engine's `Intent_config.synthesize_dag` must compute this elastically based on the parsed Intent parameters.

## 3. Execution Flow
1. **Formulate Intent**: Build a `make_intent` string detailing the target.
2. **Inject Intelligence (MIQ)**: Pipe the intent through `requiring_intelligence` constraints (`Fast_OODA`, `STPA`, `Raven`) based on problem complexity.
3. **Trigger Synthesis**: Call `Intent_config.synthesize_dag`. The Core Council's *Synthesizer* agent intercepts this and formulates the mathematical path.
4. **Elastic Spawning**: The swarm automatically spawns $N$ `Worker_Executor` fibers.
5. **Memory Commitment**: Upon successful return, verify that the `swarm_km.ml` endpoint published the execution semantic facts to the ZK network.
