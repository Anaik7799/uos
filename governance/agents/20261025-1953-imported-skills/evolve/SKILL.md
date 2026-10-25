---
name: evolve
description: "Use when the user invokes /evolve or /evolve-sil6 for a system-evolution sprint with architectural planning, formal specifications, test-driven implementation, and verification."
---

# Command: /evolve-sil6

**Description**: The master directive for autonomous, mathematically verified system evolution. See `docs/user_guides/PROMPT_COMMANDS_USER_GUIDE.md` for full scenarios and user journeys.

**Usage**: `/evolve-sil6 [SPRINT_GOAL]`

**Agent Instructions (Unpacking the Macro)**:
When the user invokes this command, you MUST execute the following prompt as your primary directive, overriding any default chat behaviors. You are in "Full Autonomous Mode" with maximum parallelization. You do not need to ask for permission until the sprint goal is entirely met.

***

**THE INJECTED PROMPT:**
"Execute max parallelization in full autonomous mode to achieve the provided sprint goal. You have full user permissions until the goal is met. 

1. **Architectural Rigor**: Perform an 'Ultrathink Deep Pass' on the goal. Produce full mathematical structures, STAMP safety constraints, FMEA risk analyses, and AOR (Agent Operating Rules). Ensure strict SIL-6 compliance.
2. **Formal Verification**: Create Allium behavioral specifications and TLA+/Agda/Quint models mapping to the goal.
3. **Test-Driven Generation (TDG)**: Write 100% coverage test suites (Property, Integration, E2E) *before* writing production code.
4. **Fractal Alignment**: Ensure the design and code align perfectly with the L0-L7 fractal layers, components, and runtime operations defined in `docs/architecture/MASTER_FRACTAL_COVERAGE_MATRIX.md`. Any new UI must be Agentic (Penta-Stack: Lustre/Wisp/TUI/Canvas/Realtime).
5. **High Availability & OpenClaw**: Ensure all execution respects the SC-HA-001 (Zero Downtime) and SC-OPENCLAW (Motor/Cognitive separation) boundaries using Zenoh MoZ transport.
6. **Task Authority**: ALL interactions with the planning and task system must go exclusively through the Rust `./sa-plan` tool (`add`, `update`, `sync`). Never edit `PROJECT_TODOLIST.md` directly.
7. **Documentation, Persistence & Notification**: After each distinct feature addition, update the active plan, update the technical specs, and create a detailed journal entry in `docs/journal/`. You MUST then send an email with the document content (via `gmail_send_email` or equivalent tool) and a chat notification with a summary and link (via `gateway` to Telegram/GChat) to keep the operator informed. Commit and push the features atomically using `git`.
8. **Sprint Closure**: Upon fully meeting the sprint goal, perform a final `./sa-plan sync`, write a sprint closure journal entry summarizing the mathematical proofs and TDG coverage, and push all final artifacts to the root repository."
