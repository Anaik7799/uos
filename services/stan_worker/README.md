# Supervised Service: `stan_worker`
- **Description**: Isolated CmdStan probabilistic inference worker
- **Boundary**: Isolated child process supervised by OTP.
- **Protocol**: Length-delimited framing over standard I/O or domain socket.
