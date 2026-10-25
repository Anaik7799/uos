# 20261025-0229 — Authenticated Mini history safety contract

Observed 2026-10-25T02:25:02.588Z

#fractal-l0 #fractal-l3 #fractal-l4 #fractal-l9 #zk-adr #zero-muda

[Plan](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md) · [Cockpit](http://nas-1.tail55d152.ts.net:4100/)

Read complete retained exchanges from the existing durable store. Authenticate fresh initData first; derive bot namespace from the configured authentication token; require explicit user/chat grant and matching stored bot identity. Unsigned or absent chat can select only a granted private chat whose ID equals the authenticated user. Signed group chat still requires an explicit grant. Browser input cannot select database, bot or arbitrary key.

## Invariants and falsifiers

Exactly bot-identity and conversation-key rows in one read; positive generation, canonical row hashes, complete context schema and exact bot/chat/user equality. Valid absent context means empty only after initialized bot binding. Errors, malformed rows and wrong scopes must show unavailable with no data. Long text is chunked losslessly by codepoint into2048byte fields; full page width must match viewport. No model calls or store writes occur in the read path. The test-only writer is confined to a new private runtime directory and uses existing native transactions.

## STPA and FMEA

Not provided: report unavailable rather than fabricate empty history. Unsafe provided: require three identity dimensions and server grants. Wrong timing: existing post-read auth/clock check refuses expired identity. Duration: existing bounded native transport and process cleanup; no retry on unknown outcome. Raw analyst1–5 FMEA: cross-user disclosure S4/O2/D3 RPN24; wrong-bot binding S4/O2/D3 RPN24; truncated text S2/O3/D2 RPN12. Mitigation tests exercise all identities, wrong database bot, duplicate/corrupt rows, longUnicode and actual persisted state changes. Residual: same-UID launcher/config trust; this is retained history, not archival recovery. Native worker refuses group-writable ancestors: observed twice in repository fixture location, resolved using private runtime directory without weakening worker policy.

## Reuse and acceptance

14existing module/FFI sources are byte-bound to accepted candidate71fa89ead730bca2f53cdccfe438499fb64bd57a; manifest in var/recovery-runtime/20261025-0219-mini-history/reuse-manifest.json. No new database or transport. Development acceptance requires unit/native/HTTP/browser observations and exact-source AGY review; fullTelegram and production admission remain NOT_GRANTED.

<details><summary>Verification domain 1</summary>

- [ ] CHK-01 Timestamp — scoped evidence above; no blanketPASS
- [ ] CHK-02 Tailnet navigation — scoped evidence above; no blanketPASS
- [ ] CHK-03 Fractal scope — scoped evidence above; no blanketPASS
- [ ] CHK-04 Knowledge links — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 2</summary>

- [ ] CHK-05 Dependency exclusions — scoped evidence above; no blanketPASS
- [ ] CHK-06 Pure graph boundary — scoped evidence above; no blanketPASS
- [ ] CHK-07 Storage safety — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 3</summary>

- [ ] CHK-08 C1-C8 — scoped evidence above; no blanketPASS
- [ ] CHK-09 Math gates — scoped evidence above; no blanketPASS
- [ ] CHK-10 Test modalities — scoped evidence above; no blanketPASS
- [ ] CHK-11 Regression — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 4</summary>

- [ ] CHK-12 GleamOTP — scoped evidence above; no blanketPASS
- [ ] CHK-13 Hermes — scoped evidence above; no blanketPASS
- [ ] CHK-14 ZigVM — scoped evidence above; no blanketPASS
- [ ] CHK-15 MAX — scoped evidence above; no blanketPASS
- [ ] CHK-16 Trace correlation — scoped evidence above; no blanketPASS

</details>

<details><summary>Verification domain 5</summary>

- [ ] CHK-17 Independentreview — scoped evidence above; no blanketPASS
- [ ] CHK-18 Jujutsu — scoped evidence above; no blanketPASS

</details>

Provenance: EV>93 NOT_ADMITTED.


[Previous](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261024-2059-telegram-current-task-bridge.md) · [Next](http://nas-1.tail55d152.ts.net:4100/files/docs/design/20261024-1044-telegram-completion-critical-path.md)

UOS footer: component evidence is not admission.
