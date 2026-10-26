# 20261026-1910 — Telegram secret hygiene and browser verification rule

#fractal-l0 #fractal-l1 #fractal-l3 #fractal-l4 #fractal-l6 #zk-adr #zero-muda #km-triad #tailscale-web

- **Contract ID**: `SC-TELEGRAM-SECRET-001`
- **Domain**: bot credentials in processes and logs; browser-driven verification from agent shells; inference credentials for the responder
- **Authority**: operator directives of 2026-10-26 ("keep the token locally with uos application in the vault", "capture screens, images and videos to verify telegram functionality"); wave 7a journal
- **Tailscale FQDN Link**: [http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261026-1910-telegram-secret-hygiene-and-browser-verification.md](http://nas-1.tail55d152.ts.net:4100/files/contracts/rules/20261026-1910-telegram-secret-hygiene-and-browser-verification.md)
- **Status**: ACTIVE — process rule; grants no authority and no admission

[Cockpit](http://nas-1.tail55d152.ts.net:4100/) · [Journeys skill](http://nas-1.tail55d152.ts.net:4100/files/.claude/skills/uos-telegram-journeys/SKILL.md) · [Wave 7a journal](http://nas-1.tail55d152.ts.net:4100/files/docs/journal/20261026-1930-claude-telegram-wave7a-residuals-review-bridge-hygiene-and-mini-app-cdp.md) · [ZK](http://nas-1.tail55d152.ts.net:4100/zk) · [Wiki](http://nas-1.tail55d152.ts.net:4100/wiki)

Transclusions: `[[zk:20260905-1801-moc-uos-unified-master]]` · `[[wiki:20260905-1801-uos-zk-km-corpus-index]]`

## 1. Why this rule exists

On 2026-10-26 the production bridge (`tools/telegram_client.exe --poll`) was found to pass the bot URL to curl in its argument vector and to print the whole command, token included, into the user journal on every `getUpdates` failure. The same day, a Chrome DevTools verifier could not complete any URL load from the agent shell, and the cognitive worker was found answering every free-text message with the deterministic `/status` default because its OpenRouter credential is missing. Each was fixed or recorded under a Sa-plan task; this rule keeps them from recurring.

## 2. Invariants

- **INV-TGS-01 (no secret in argv).** A bot token, vault passphrase or API key never appears in a process argument vector. A curl call carries its URL as a config file on stdin (`-K -`); an OCaml or Gleam caller reads the credential inside its own process from the vault store or a systemd credential directory.
- **INV-TGS-02 (no secret in logs).** Every error string that could echo a URL or a header passes a redaction function before it is returned, printed or journaled (`redact_token` in `tools/telegram_client.ml`; `egress_redactor` in Gleam). A journal line matching `bot[0-9]+:[A-Za-z0-9_-]{20,}` is a P1 defect.
- **INV-TGS-03 (verification before lease release).** A production bridge or worker is restarted only under its `runtime:<service>` coordinator lease and a claimed Sa-plan task; the restart is verified (unit active, poll child present, `getMe`, zero secret lines) before the lease is released; a rollback copy exists before the install.
- **INV-TGS-04 (browser verification runs where the browser can load).** Headless Chrome completes no URL load from the agent shell sandbox on nas-1 (wave 7a net-log evidence). Browser-driven verification is built as a pure OCaml CDP tool and executed from the operator terminal with the `!` prefix; its receipt under `var/` is the evidence. A sandbox bypass is not a substitute.
- **INV-TGS-05 (typed reason, never silent fallback).** When the inference path is unavailable the responder's `intent/res` record and the reply carry a typed reason (`inference_unavailable:<cause>`); a canned directive reply presented as an answer is a defect (observed as `dispatch_directive_status_default` for messages 2244 and 2246).
- **INV-TGS-06 (credential provisioning is an operator act).** An OpenRouter key or a staging bot token is supplied by the operator through the vault or a systemd `LoadCredential`; agents record its absence and never fabricate, search for, or copy one.

## 3. Checks

```bash
# secret exposure after any bridge restart
journalctl --user -u uos-telegram-bridge --no-pager -o cat --since "-10 min" | grep -cE 'bot[0-9]+:[A-Za-z0-9_-]{20,}'   # must print 0
pgrep -a -x curl | grep -cE 'api\.telegram\.org/bot'                                                                  # must print 0
# responder credential presence (names only)
journalctl --user -u uos-cognitive-worker --no-pager -o cat -n 50 | grep -c 'OPENROUTER_API_KEY missing'              # 0 once provisioned
```

## 4. Limits

This is a convention plus the two grep checks above; nothing enforces it at runtime. EV ceiling 93; EV-94..109 NOT_ADMITTED; no new EV number is minted.

**UOS footer:** `nas-1.tail55d152.ts.net:4100` · Sa-plan is the sole execution authority; this rule grants no admission.
