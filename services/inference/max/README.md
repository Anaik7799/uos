# Supervised Service: `inference/max`
- **Description**: Isolated Modular MAX/Mojo pinned runtime worker (Python strictly confined here)
- **Boundary**: Isolated child process supervised by OTP.
- **Protocol**: Length-delimited framing over standard I/O or domain socket.
