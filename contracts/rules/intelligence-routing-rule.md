# 20260907-0930- Global Intelligence Routing Rule

- **Contract ID**: `SC-INTEL-ROUTING-001`
- **Authority**: Operator directive 2026-09-07 ("use the cheapest intelligence available for a required operation; globally optimize from Claude, Codex, AGY or OpenRouter for all operations; full symbiosis")
- **Design**: `docs/design/20260907-0925-uos-global-intelligence-routing-design.md` (`DES-UOS-INTEL-ROUTING-001`)
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0925-uos-global-intelligence-routing-design.md](http://nas-1.tail55d152.ts.net:4100/docs/docs/design/20260907-0925-uos-global-intelligence-routing-design.md)
- **Status**: ACTIVE for dispatch decisions by every agent surface (Claude, Codex, Gemini/Antigravity, .agents); implementation of the automatic router is paused with the rest of implementation.

## Rule
1. Every operation is routed to the cheapest tier whose measured adequacy meets the class threshold, within the operation's budget and the coordination policy's authorization: `route(o) = argmin cost(t,o) s.t. P(adequate(t,o)) ≥ θ(o), cost ≤ budget(o), authorized(t,o)`.
2. Default routes: R0 runtime control → deterministic code (0 tokens); R1 mechanical verification → script, else Haiku; R2 docs/summaries → Haiku or OpenRouter nano; R3 advisory second opinion → OpenRouter nano (≤ USD 0.02, ≤ 512 tokens, 30 s, allowlist, no private source); R4 bounded implementation → Sonnet; R5 sovereign security/architecture review → Codex Astra and Antigravity; R6 design authority, integration, admission → Fable only (policy `design_models`).
3. Escalation is one step to the next-cheapest adequate tier; a second failure is a jidoka stop for the L0 authority. Adequacy posteriors per (tier, class) are updated only from verified outcomes, never from self-report.
4. Free tiers are tried first when their data policy admits the payload class; refusals are cached for an hour, then the paid floor applies.
5. Every routing decision and outcome is a board message (`Dispatch` with class, tier, estimated cost, reason; `Report` with actual cost and adequacy) so the global spend per agent and per class is visible in the shared `usage` state.
6. The router lowers cost, never authority: sanitized payloads only for external tiers; credentials from the approved environment only; no tools and no side effects on advisory tiers.
