# Mission-Critical Swarm Architecture (15+N+M)
**Timestamp**: 2026-08-10T09:12:00+02:00
**Location**: `modules/swarm/docs/architecture/FULL_ARCHITECTURE_DIAGRAM.md`

This document visualizes the complete cyber-physical architecture of the Swarm Engine, incorporating the 15-Agent Core Council, the 4-Tier CRDT Memory Substrate, and the Zenoh Network Mesh.

## Global Topology Diagram

```mermaid
graph TD
    %% Core Inputs
    UserIntent[Declarative Intent / ADK Config] --> Synthesizer

    %% The 15-Agent Core Council
    subgraph Core Council (The 15 Static Brains)
        direction TB
        
        %% Intelligence Routing
        Synthesizer((1. Synthesizer)) --> |DAG Synthesis| Conductor
        NeuralWeaver((5. Neural Weaver)) -.-> |AI/ML Optimizations| Synthesizer
        
        %% Safety & Verification
        CyberNav((2. Cybernetic Navigator)) --> |STPA / Fast_OODA| Synthesizer
        Byzantine((9. Byzantine Sentinel)) --> |BFT Consensus| CyberNav
        Bayesian((4. Bayesian Critic)) --> |Rete_UL Audit| Conductor
        Chrono((10. Chrono-Arbiter)) --> |RTOS Deadlines| Conductor
        Crypto((11. Crypto Sentinel)) --> |Anti-Tamper| ZenohMesh
        
        %% Data & Memory Handling
        Conservator((3. Knowledge Conservator)) --> |RAG & Semantic Sync| ZenohMesh
        Topologist((7. Topologist)) --> |CRDT Mesh Routing| ZenohMesh
        
        %% Physics & Kinematics
        Fluidic((14. Fluidic Controller)) --> |Thermodynamics| Conductor
        Kinematic((13. Kinematic Weaver)) --> |SLAM / Spatial| Conductor
        Quantum((12. Quantum Arbiter)) --> |True RNG| NeuralWeaver
        HiveMind((15. Swarm Hive-Mind)) --> |Gossip Protocol| ZenohMesh
        Sensorium((8. Sensorium)) --> |DSP| ZenohMesh
    end

    %% Elastic Fabric
    Conductor((6. Conductor)) ===> |Spawns N Fibers| ElasticFabric
    
    subgraph The Elastic Fabric (N = width)
        Worker1[Worker Executor 1]
        Worker2[Worker Executor 2]
        WorkerN[Worker Executor N...]
    end

    %% Fractal Satellites
    Conductor -.-> |Summons M Domain Experts| Satellites
    subgraph Fractal Satellites (M)
        Formal[The Formal Sentinel]
        Other[Other Specialized Satellites]
    end

    %% Execution & PubSub
    ElasticFabric ===> |Pub/Sub| ZenohMesh
    Satellites ===> |Pub/Sub| ZenohMesh

    %% Data Bus
    subgraph Zenoh Network Mesh
        topic1(swarm/sensorium/telemetry)
        topic2(swarm/topologist/crdt)
        topic3(swarm/sentinel/bft)
        topic4(swarm/conductor/actuate)
    end

    %% Physical Actuators
    topic4 ===> PhysicalWorld[IoT Actuators / Robotics]
    PhysicalWorld -.-> |20kHz Sensor Feed| topic1

    %% Memory Substrate
    topic2 ===> Memory
    subgraph 4-Tier Memory Substrate
        WM[(Working Memory\nCRDT)]
        EM[(Episodic Memory\nEvent Log)]
        SM[(Semantic Memory\nZK Graph)]
        PM[(Procedural Memory\nCompiled DAGs)]
    end
```

## System Lifecycles

### 1. Intent Synthesis & Routing
When a `Declarative Intent` is received, the **Synthesizer** injects the mandated MIQ services (e.g., `Raven`, `Fast_OODA`). The **Neural Weaver** (using AI/ML pattern recognition) assists the Synthesizer in building an optimal, non-linear DAG.

### 2. Execution & Elastic Scaling
The synthesized DAG is handed to the **Conductor**. The Conductor calculates the topological width and summons exactly $N$ **Worker Executors** (Elastic Fabric) and $M$ **Domain Experts** (Fractal Satellites). The **Chrono-Arbiter** polices the threads to guarantee nanosecond deadlines are not violated.

### 3. Cyber-Physical Interactions
The **Sensorium** subscribes to the Zenoh `telemetry` topic, ingesting 20kHz physical hardware data (bypassing the OODA loop). Physical interactions are constrained by the **Fluidic Controller** (heat/thermodynamics) and the **Kinematic Weaver** (spatial coordinates). Output commands are routed to the Zenoh `actuate` topic.

### 4. Zero-Trust & BFT
The entire execution is wrapped in a mathematical shield. The **Cryptographic Sentinel** encrypts the data streams against quantum threats, while the **Byzantine Sentinel** ensures state matrices remain untampered by hardware faults or radiation bit-flips.

### 5. Memory & Homeostasis
All state changes flow through the **Zenoh Mesh** into the 4-Tier CRDT Memory. The **Topologist** routes high-throughput CRDT syncs, while the **Knowledge Conservator** ensures long-term facts are published back to the external Zettelkasten/Wiki networks.
