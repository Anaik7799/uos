# Supervised Service: `solver_worker`
- **Description**: Bounded Z3 SMT solver worker with normalized queries and timeouts
- **Boundary**: Isolated child process supervised by OTP.
- **Protocol**: Length-delimited framing over standard I/O or domain socket.
