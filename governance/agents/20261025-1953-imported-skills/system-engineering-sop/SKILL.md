---
name: system-engineering-sop
description: Standard Operating Procedure for safe-state design and hardening of safety-critical systems (SIL-4/SIL-6). Covers BIST/POST logic, telemetry, HMI hardening, and fault injection testing.
---
**Domain**: Architecture & Systems Engineering
**Focus**: Safety-critical systems, deterministic boot, and high-assurance operations.
This Standard Operating Procedure (SOP) serves as a technical blueprint for architects designing "Greenfield" systems or "Hardening" legacy infrastructures for safety-critical environments (e.g., SIL-4/SIL-6).
# Phase 1: Architectural "Safe-State" Design
1.  **Establish Determinism**: Design the startup sequence so that every event is time-bounded. Use Fixed-Priority Preemptive Scheduling to ensure safety checks never wait behind non-critical tasks.
2.  **Define the "Quiet Boot" Paradox**: During design, ensure the system can boot silently for the operator, but maintain a High-Fidelity Log in the background. **Skillset:** The ability to parse hex-dumps into human-readable fault trees.
3.  **Hardware-Root-of-Trust (RoT)**: Implement a Trusted Platform Module (TPM) or Hardware Security Module (HSM). The system must prove its integrity to itself before it can prove it to the operator.
# Phase 2: Implementation of BIST/POST Logic
1.  **Destructive vs. Non-Destructive Testing**:
*   **Skill**: Write memory tests that can verify RAM integrity without wiping the configuration data required for the boot.
*   **Instruction**: Use March C- algorithms for memory testing to catch "coupling faults" between adjacent memory cells.
2.  **The "Babbling Idiot" Filter**:
*   **Skill**: Design network bus guardians.
*   **Instruction**: If a sub-component (like a naval sonar sensor) begins flooding the bus during POST, the master controller must have the hardware capability to physically disconnect that node's TX line.
3.  **Power Sequencing Logic**:
*   **Instruction**: Never initialize high-voltage actuators or nuclear control rods until the low-voltage logic (FPGA/CPU) has confirmed a $3\sigma$ (Three Sigma) stability on the power rails for at least 100ms.
# Phase 3: Telemetry and Forensic Strategy
1.  **Black Box Synchronization**:
*   **Skill**: Implement Circular Buffering for logs.
*   **Instruction**: The startup log must be written to non-volatile memory (NVRAM) in real-time. If a "Hard Reset" occurs mid-POST, the system must be able to read the last known good step upon reboot to perform a "Differential Diagnosis."
2.  **The "Golden Image" Comparison**:
*   **Instruction**: Maintain a read-only "Golden Copy" of the firmware. During every boot, the system must perform a bit-for-bit comparison or a cryptographic hash check of the running image against the Golden Copy.
# Phase 4: Human-Machine Interface (HMI) Hardening
1.  **Avoid "Alarm Fatigue"**:
*   **Skill**: Implement Alarm Grouping.
*   **Instruction**: If the power supply fails, don't show 50 individual sensor errors. The HMI must suppress the 50 "Low Voltage" symptoms and highlight the 1 "Power Supply Failure" root cause.
2.  **The "Lamp Test" Protocol**:
*   **Instruction**: Every startup must include a visual/audible "All-Call." Every pixel, LED, and siren must activate briefly. If a "Warning" bulb is burnt out, the system is No-Go.
# Phase 5: Verification & Validation (V&V)
1.  **Fault Injection Testing**:
*   **Skill**: "Red Teaming" the startup.
*   **Instruction**: During the hardening phase, intentionally snip a wire, short a capacitor, or corrupt a firmware bit. If the BIST/POST does not catch the specific fault and prevent the system from entering "Operational Mode," the diagnostic coverage is insufficient.
2.  **Regression Testing**:
*   **Instruction**: Any update to a sub-component requires a full re-validation of the Startup Timing Budget. A 50ms delay in a naval fire-control system boot could be catastrophic.
# Summary Checklist for the System Designer
*   **Isolation**: Can a failure in a non-critical component (e.g., cabin lights) stop the critical boot (e.g., flight controls)? (Goal: No)
*   **Coverage**: Does the BIST check at least 99% of all logic gates and memory bits?
*   **Latency**: Is the time from "Power On" to "Safe State" under the required threshold?
*   **Security**: Is the boot path encrypted and signed?
*   **Integration**: Is Git Intelligence fully integrated with the CEPAF ignition sequence to ensure a controlled startup? Are Zenoh, MCP, Quadruplex logging, and OTEL telemetry active and verifiable?