# Supervised Service: `planning_worker`
- **Description**: Supervised SQLite planning and migration ledger worker
- **Boundary**: Isolated child process supervised by OTP.
- **Protocol**: Length-delimited framing over standard I/O or domain socket.
