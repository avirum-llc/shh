# shh — grilled spec

Source: `shh-plan.md` (v0.1 draft, 2026-04-19)

## What the spec already answers well
- Problem statement and threat model (§1, §8) — concrete, cited, specific vectors
- Target audience tiers (§2) — primary/secondary/tertiary with an explicit "not audience"
- Functional reqs (§6) — detailed, mostly testable
- Non-functional reqs (§7) — latency/memory budgets defined
- Tech stack (Part 2) — reasoned choices, alternatives rejected
- Design system (Part 4) — 5 surfaces, tokens, type scale, motion rules
- Scope ladders (§11) — v0.1/v0.5/v1.0 feature lists

## Gaps / weak spots to grill
1. **Motivation & stake** — is this scratch-own-itch, portfolio, or income-seeking? Affects scope/polish/timeline.
2. **Swift 6 / SwiftNIO / XPC experience** — "2 weekends for v0.1" is aggressive without prior Swift shipping experience.
3. **CLI `*_BASE_URL` honoring** — acknowledged risk, but no evidence of per-CLI validation yet. #1 technical risk.
4. **Token counting under streaming** — Q3 acknowledged, no resolution. Determines trust in the spend number.
5. **Budget cap race conditions** — concurrent requests vs atomic check-and-increment.
6. **Competitive pressure from Keycard** — what if they ship proxy+tracker before v0.1? Wedge collapses.
7. **Anthropic shipping built-in secrets mgmt** — #29910 is a public signal they might. Timeline risk.
8. **XPC channel hardening** — keys cross the boundary between menubar app and proxy. Attack surface.
9. **Self-signed cert vs HTTP loopback (Q1)** — unresolved, blocks design.
10. **Migration/schema evolution story** — Keychain + SQLite schemas lock in once users arrive.
11. **Business model / what "done" means** — no Pro tier defined, no revenue target, no sustainability plan.
12. **Definition of success for v0.1** — "works for me" is stated but no go/no-go threshold before v0.5.
13. **Time budget / hours/week available** — solo indie, no stated commitment.

## Grill log

### Resolved

**Motivation (Q1).** Scratch-own-itch. Real pain: keys across OpenAI, Anthropic, Gemini, Clerk, Vercel, all pay-per-use. Distribution is Claude's responsibility post-build (computer use on user's accounts).

**Swift/Mac experience (Q2, retracted).** Manish has shipped 4 iOS apps and a macOS app (Roast, MAS submission track) as of 2026-04-18. `KeychainHelper.swift` already exists. Signing/notarization pipeline familiar. No prior `MenuBarExtra`, XPC services, or SwiftNIO — not a blocker. "Timelines are irrelevant — we take as long as it takes."

**Key selection / request routing (Q3).** Project-scoped. Each project gets **primary + optional secondary** key per provider. Tokens are written into project-local config (`.claude/settings.json` etc). Dummy token identity encodes project+key; proxy does simple lookup. "Project" defaults to git repo root or user-picked folder. JIT setup prompt on first unrecognized call from a new project.

**Secondary key role (Q4).** **User-configurable per project:** options include no fallback, fallback on cap hit, fallback on provider error, or cycle. "Public" was a misspeak for **work**. Accounting buckets: `personal` / `work`. Cross-bucket fallback (personal↔work) requires explicit opt-in — silent routing between wallets is a footgun.

**Cost accuracy + cap enforcement (Q5).** Tokenize locally (tiktoken / provider tokenizers / byte-level fallback). Reconcile async against provider billing APIs where read-only access exists (Anthropic has this, OpenAI partial, Gemini limited). UI labels numbers as **estimated** until reconciled; post-reconcile, label as **verified**. Cap enforcement happens pre-request using a worst-case estimate — if starting the request might exceed cap, reject with 429. Never sever an in-flight stream (would corrupt Claude Code output). Implication: caps can overshoot on the last request of the day; acceptable. Schema needs 4D token fields: input / cached_input / cache_write / output.

**Audience sharpening (Q6).** **API-key users only.** Subscription users (claude.ai Max/Pro/Teams, Cursor hosted mode, Codex OAuth plans) are explicitly out of scope. Positioning: "`shh` is for developers who pay-per-token across providers." The PRD's secondary audience (non-engineer PMs on Claude Code) mostly dissolves — most are subscription users. Primary audience: multi-provider API-key devs. Launch channels re-rank toward dev-heavy (HN, r/ClaudeAI devs, awesome-lists) and away from PM-discovery.

**Transport (Q7).** **HTTP on loopback by default.** HTTPS is security theater on `127.0.0.1` — no wire to tap — and the cost of default-HTTPS is a system-trusted root CA that, if exfiltrated, lets an attacker MITM the user's entire internet. Contradicts the brand. HTTPS remains an escape hatch: only enabled for CLIs that refuse `http://`, per-user CA name-constrained to `127.0.0.1`, private key kept in Keychain. Resolves PRD Q1.

### Open / in-progress
- Shadow mode (Q4 in PRD) — onboarding / growth hook
- MCP server for spend queries: keep or cut?
- Success criteria for v0.1 → v0.5 go/no-go
- (deferred to plan/research) Anthropic shipping built-in secrets mgmt — strategic; doesn't kill multi-provider wedge
- (deferred to plan) proxy-down UX, price-table update strategy, schema evolution
