# Supervised Service: `rule_engine_worker`
- **Description**: Isolated Rete-UL rule evaluation worker
- **Boundary**: Isolated child process supervised by OTP.
- **Protocol**: Length-delimited framing over standard I/O or domain socket.
