# Services Subsystem (`services/`)

- **Ownership & Language Authority**: Supervised isolated processes.
- **Scope**: Auxiliary daemons, including `services/inference/max` (Modular MAX/Mojo pinned runtime).
- **Invariants**: Python is strictly confined to `services/inference/max`. All services communicate via structured contracts and are supervised by OTP.
