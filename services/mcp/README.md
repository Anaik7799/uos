# UOS Unified MCP Service (SC-MCP-001)

## Overview
This service unifies C3I planning/telemetry MCP tools with ZigVM harness evidence/OODA tools into a cohesive control loop.

## Architecture
- Transport: JSON-RPC 2.0 over stdio, HTTP (Wisp), and Zenoh pub/sub.
- Planning & Telemetry: Powered by Gleam/OTP and SQLite.
- Evidence & Control Loop: Powered by Hermes/ZigVM harness and OODA log.
- Safety & STAMP: Continuous safety census (54 UCAs, band enforcement).
