# shh — Research findings

Phase 2 output. 5 parallel subagents: CLI compatibility, API-key regex catalog, competitive landscape, Mac stack patterns, token counting / cost reconciliation. All cited; this doc is the synthesis.

---

## 1. CLI compatibility — which CLIs can actually be proxied

| CLI | Proxyable | How | Gotcha |
|---|---|---|---|
| **Claude Code** (`@anthropic-ai/claude-code`) | Yes | `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` (Bearer) — NOT `ANTHROPIC_API_KEY` (that's `x-api-key` and doesn't work with custom URL) | Telemetry hits `statsig.anthropic.com` + `sentry.io` directly, bypassing base URL. Disable with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`. Warn users: this also kills 1M context + /remote-control. Setting `ANTHROPIC_AUTH_TOKEN` breaks OAuth subscribers (issue #33330) — irrelevant since we're API-key-only. |
| **OpenAI Codex** (`@openai/codex`) | Yes | `OPENAI_BASE_URL` + `OPENAI_API_KEY` against built-in provider | Custom-provider env-only path is flaky (issue #652). Stick with the built-in provider. |
| **Aider** | Yes | `OPENAI_API_BASE` / `ANTHROPIC_API_BASE` via LiteLLM backend | Cleanest target of the six. |
| **OpenCode** (`sst/opencode`) | Yes, but | Requires writing/merging `opencode.json` — no env-var wrapper. | `shh connect opencode` patches the config file, not the env. |
| **Gemini CLI** (`@google/gemini-cli`) | Yes | `GOOGLE_GEMINI_BASE_URL` + `GEMINI_API_KEY` | SDK explicitly whitelists `localhost` / `127.0.0.1` in its HTTPS check — best-behaved CLI here. Sandbox mode drops the env var (issue #2168). |
| **Cursor CLI** (`cursor-agent`) | **No** | All traffic routes through Cursor backend (`streamFromAgentBackend`) regardless of env vars. | **Drop from v0.1 scope.** Document as unsupported. |

**Decisions:**
- HTTP on loopback (Q7) is validated — 5 of 6 CLIs accept `http://127.0.0.1:PORT` without warnings.
- Drop Cursor from v0.1. Already aligned with Q6 (API-key-only audience).
- Claude Code connect flow: set `ANTHROPIC_AUTH_TOKEN` (Bearer), set telemetry-disable vars, warn about 1M-context tradeoff.
- OpenCode connect flow writes to `opencode.json`; others use env vars or CLI-specific config files.
- Don't try to intercept OAuth bootstrap — none of these route OAuth through `*_BASE_URL`, and we're API-key-only.

---

## 2. API-key regex catalog (scanner)

**Tier 1 — LLM providers (proxied + metered):**

| Provider | Pattern | FP risk |
|---|---|---|
| Anthropic | `sk-ant-(?:api\|admin)\d{2}-[A-Za-z0-9_\-]{80,120}` | Very low |
| OpenAI | `sk-(?:proj\|svcacct\|admin)-[A-Za-z0-9_\-]{20,200}` or legacy `sk-[A-Za-z0-9]{48}` | Low — prefer project form |
| Gemini | `AIza[0-9A-Za-z_\-]{35}` | **High** — shared with all Google keys (Maps, YT, Firebase); disambiguate via env-var name (`GEMINI_`, `GOOGLE_API_KEY`) |
| Groq | `gsk_[A-Za-z0-9]{52}` | Low |
| Replicate | `r8_[A-Za-z0-9]{37,40}` | Low |
| Hugging Face | `hf_[A-Za-z0-9]{34,40}` | Low |
| Perplexity | `pplx-[A-Za-z0-9]{48,56}` | Low |
| xAI | `xai-[A-Za-z0-9]{80}` | Low |
| Together / Mistral / Cohere | No documented prefix | **Env-gate required** |

**Tier 2 — Paid services (hero scope, stored only):**

- Distinct prefixes (low FP): Resend `re_`, PostHog `ph[cx]_`, LaunchDarkly `api-`, Sentry DSN URL, Twilio `SK/AC[hex]{32}`, SendGrid `SG.`, Neon `napi_`, Planetscale `pscale_{pw,tkn,oauth}_`.
- **Stripe vs Clerk `sk_live_` collision**: disambiguate by length (Stripe ≥99) + env-var name (`STRIPE_` vs `CLERK_`).
- **Env-gate required** (undocumented): Vercel, Railway, Supabase (JWT parse), Firebase (shared with Gemini), Segment, Mixpanel, Datadog, Auth0.

**Tier 3 — Broader secrets (stored only):**

- GitHub PATs: `gh[pousr]_[A-Za-z0-9]{36}` (classic) / `github_pat_[A-Za-z0-9_]{82}` (fine-grained)
- AWS: `(?:AKIA|ASIA)[A-Z0-9]{16}` (access key); secret requires context-key gate
- GCP service account: file-level JSON detection for `"type": "service_account"`
- Slack webhooks, Discord bots, Linear, Notion (`secret_` or `ntn_`), npm `npm_`, Cloudflare

**Tier 4 — Flag, DO NOT store in v0.1:** SSH private keys (PEM header), JWTs (three base64 segments).

**Scanner design principle: two-signal classifier.** Regex match + env-var / config-key context. Regex-alone produces too many FPs on undocumented formats; the env name (`STRIPE_SECRET_KEY=`, `export TOGETHER_API_KEY=`) resolves almost all ambiguity.

---

## 3. Competitive landscape (April 2026)

| Product | Shape | Threat level |
|---|---|---|
| **Keycard** (keycard.studio) | **Live, MIT, Mac-native, vault-only.** Clipboard capture + subprocess env injection. No proxy, no cost tracking. HN reception skeptical. | **Owns the vault slice.** shh differentiates on proxy + cost tracker + multi-provider. |
| **VaultProof** (v0.4.2, active) | Hybrid cloud — splits keys client-side, proxy through their servers. Freemium ($0 / 10k calls). OSS client, closed backend. | Different trust model; doesn't compete on local-only story. |
| **Vault-AI, SecureCode, Lade, keychains.dev** | All cloud- or server-oriented; none Mac-native solo-dev apps. | Low. |
| **Anthropic issues #29910, #23642** | Both **OPEN**. No staff comments. No roadmap. Community workarounds only. | Window is open. No imminent threat. |
| **Apple Tahoe (macOS 26)** | Shipped Foundation Models + Xcode 26 ChatGPT integration. **No** key-vault feature. Tahoe actually broke `security find-generic-password` CLI reads (six Keychain regressions). | No threat; active headwind for anyone relying on CLI Keychain tools. |
| **LiteLLM / Helicone / Langfuse** | All team/cloud. Helicone acquired by Mintlify Mar 2026. None Mac-native for individuals. | Low. |
| **1Password Unified Access** (Mar 2026) | Enterprise AI-agent governance. Partners: Anthropic, OpenAI, Cursor, Vercel. CLI/SDK-only. Subscription. | Enterprise-only; different audience. |

**Verdict (from agent):** *"Nobody has shipped vault + loopback HTTP proxy + multi-provider cost tracker in one Mac-native OSS app. The three-in-one combo is still wide open. Ship fast; lead with proxy + cost-tracker differentiators; vault is table stakes now."*

**Implication for shh positioning:** soften the vault pitch (Keycard exists with a comparable vault), lead with *"vault + proxy + real-time multi-provider spend tracker in one Mac-native app."* The combination is the unique claim. This changes the HN title and README hero.

---

## 4. Mac stack patterns

**User's existing Swift code** (TodyAI, WTFMode, Roast): extensive iOS work, recent macOS shipping. `KeychainHelper.swift` uses plain `SecItem` without access control or biometric gating — suitable for iOS session tokens, **not** for LLM API keys. shh rebuilds the Keychain layer with `kSecAttrAccessControl` + `.biometryCurrentSet` + LAContext. No existing `MenuBarExtra` code — builds from zero.

**Key patterns:**

1. **MenuBarExtra `.window` style** — no programmatic dismiss API; use the [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) OSS library. `NSApplication.ActivationPolicy.accessory` to hide from Dock. `.monospacedDigit()` for spend numbers.

2. **SwiftNIO in XPC service** — separate target, `launchd` plist with `KeepAlive=true` + `MachServices` for auto-restart <2s. Use high port (18888) to avoid conflicts. Main app ↔ proxy via typed XPC interface.

3. **Name-constrained CA: macOS does NOT enforce `nameConstraints`** even though RFC 5280 §4.2.1.10 defines it. Must use per-user CA in login Keychain + manual `SecTrustEvaluateWithError` pinning. Never install to System Trust. (Affects only the HTTPS escape hatch; HTTP-only path is fine.)

4. **LAContext + Keychain recipe:**
   ```swift
   let ac = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil)
   let ctx = LAContext(); ctx.touchIDAuthenticationAllowableReuseDuration = 300
   // SecItemAdd with kSecAttrAccessControl = ac
   // SecItemCopyMatching with kSecUseAuthenticationContext = ctx
   ```
   5-min reuse window means one Touch ID prompt per session, not per request.

5. **CLI bundled in `.app`** — sign nested binary with `--entitlements` + `-o runtime` **before** signing the app. Notarize the full DMG. First-run symlink to `/usr/local/bin/shh` with user consent.

6. **Sparkle 2 + GitHub Releases** — EdDSA keys (private stored in Keychain), `SUFeedURL` → `appcast.xml` at repo root, auto-generate with Sparkle's `generate_appcast` tool.

---

## 5. Token counting & cost reconciliation

| Provider | Local pre-request estimate | Post-request truth | Async reconcile |
|---|---|---|---|
| **Anthropic** | **Not possible locally** — no public tokenizer for Claude 3+. Opus 4.7 tokenizer produces ~35% more tokens than 4.6. Use `len(text)/3` rough heuristic for UI preview only. | Final stream chunk `usage` (4D: input / cache_creation / cache_read / output) | `/v1/messages/count_tokens` — free, ~100 RPM on Tier 1. Use as async reconciler, **not** sync gate. |
| **OpenAI** | **[TiktokenSwift](https://github.com/narner/TiktokenSwift)** — UniFFI to real Rust `tiktoken`, 0% drift. Handles GPT-5/5.1 via `o200k_base`. | `stream_options.include_usage = true` on final chunk. Codex already sets this. | N/A — local is accurate. |
| **Gemini** | Byte-length heuristic is acceptable. | `usageMetadata` on final stream chunk: `promptTokenCount`, `cachedContentTokenCount`, `candidatesTokenCount`, `thoughtsTokenCount` (reasoning). | Gemini 3 flash-preview has known `thoughtsTokenCount` bug (Jan 2026). |

**Billing APIs for reconciliation — mostly UNAVAILABLE for individuals:**
- Anthropic Usage & Cost Admin API → requires **organization Admin key**, not personal accounts.
- OpenAI Usage API → org-admin-only.
- Google Gemini Developer API (AI Studio) → no first-class programmatic pull.

**Decision: drop "verified" label from v0.1.** All numbers stay "estimated" for personal-key users. Honest UI. If users add org-admin keys later, reconciliation becomes available in a v0.5+.

**Pricing dimensions (April 2026, per 1M tokens):**

| Model | Input | Cache create | Cache read | Output |
|---|---|---|---|---|
| Claude Opus 4.7 | $15 | $18.75 | $1.50 | $75 |
| Claude Sonnet 4.6 | $3 | $3.75 | $0.30 | $15 |
| Claude Haiku 4.5 | $1 | $1.25 | $0.10 | $5 |
| GPT-5 | $1.25 | — | $0.125 | $10 |
| GPT-5.5 | $2 | — | $0.20 | $16 |
| Gemini 2.5 Pro (≤200K) | $1.25 | — | $0.3125 | $10 |
| Gemini 3 Pro (≤200K) | $2 | $0.50 | — | $12 |

Bundle as `prices.json`; fetch updates from signed manifest at `github.com/avirum-llc/shh-prices` (per PRD FR-C2).

---

## 6. Consolidated implications for the plan

1. **Drop Cursor** from v0.1. Document as known limitation.
2. **Claude Code connect** sets `ANTHROPIC_AUTH_TOKEN` (Bearer), telemetry-disable vars; warns about 1M-context tradeoff.
3. **OpenCode connect** patches `opencode.json` rather than setting env vars.
4. **HTTPS escape hatch** is niche and even more painful than thought (name-constrained CAs unenforced on macOS). Ship v0.1 as HTTP-only; revisit only if a specific CLI forces it.
5. **Scanner** ships as a versioned JSON pattern catalog with two-signal classification (regex + env-name context).
6. **Token counting** stack: TiktokenSwift for OpenAI, `count_tokens` async for Anthropic, `usageMetadata` for Gemini.
7. **UI label** is permanently "estimated" for personal-key users. No fake "verified" claim.
8. **Positioning** softens the vault pitch; leads with the combination (vault + proxy + tracker).
9. **MCP server and shadow mode** are cut from v0.1 (deferred or removed).

## Open items (decide at plan-review)

- **License**: MIT (PRD default) vs AGPL (cmux's choice — prevents closed-source forks).
- **Bundle ID** / **Homebrew tap** names — confirm `com.avirumapps.shh` and `avirumapps/homebrew-shh`.
- **Apple Developer team ID** — presumably the same as Roast; confirm.
