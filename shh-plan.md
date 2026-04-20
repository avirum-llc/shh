# SHH

**Product Requirements, Build Plan, and Distribution Strategy**

| | |
|---|---|
| **Product** | `shh` |
| **Tagline** | Your AI keys never speak above a whisper |
| **Home** | `shh.avirumapps.com` |
| **Author** | Manish Singh |
| **Version** | 0.1 (draft) |
| **Status** | Exploration |
| **Last updated** | April 19, 2026 |

---

## TL;DR

`shh` is a native macOS menubar app that stores LLM API keys in Apple Keychain, injects them into AI coding tools (Claude Code, Codex, Cursor) through a local proxy so the agent never sees the real key, and tracks combined spend across providers in real time.

Three letters, one job: **make sure your AI tools never speak your secrets out loud.**

Open source, local-first, biometric-gated. The wedge: nobody has shipped a vault + proxy + cost tracker in one product, and the existing CLI workarounds (1Password + `op run`) are too high-friction for the non-engineer audience that AI coding tools are now onboarding.

---

# Part 1 — Product Requirements

## 1. Problem

Anyone using AI coding agents (Claude Code, Codex, Cursor, Aider) accumulates a pile of API keys from multiple providers. Today there is no good way to manage them safely or visibly.

### What's broken today

- Keys live in plaintext `.env` files, scattered across projects and shell config.
- Claude Code and similar agents can read `.env` files into their context window, exposing secrets to the LLM and to log capture.
- Even when keys are stored in 1Password and injected via `op run`, child processes inherit them — and Claude Code captures stdout, meaning a single `printenv` or a stack trace can leak the key.
- Spend is invisible. A user with Anthropic + OpenAI + Gemini keys must check three billing dashboards, on three different cycles, to know what they've spent today.
- There are no guardrails. A runaway agent loop can burn $200 before the user notices.
- The existing solutions (1Password CLI, Doppler, Infisical) require shell wrapper scripts and process-replacement knowledge that excludes the non-engineer population AI tools are now onboarding.

### Why now

- Anthropic has an open feature request (claude-code #29910, March 2026) for built-in secrets management in Claude Code, explicitly citing the non-engineer audience as the gap.
- A second issue (#23642) requests `op://` reference support directly in `settings.json`.
- Public writeups (e.g. *"Your Vault Protects Your Secrets Until Claude Code Runs Your Tests"*, Feb 2026) have established that the prompt-injection / process-inheritance threat model is real and widely understood.
- LLM API spend is now significant for individuals and small teams, with Opus, GPT-5, and Gemini Pro all in the $5–30 per million output token range.
- The pre-launch competitor Keycard (keycard.studio) validates demand but takes the obvious "vault" lane — leaving the proxy + cost tracker positioning open.

## 2. Target audience

**Primary.** Solo developers and small-team developers who use multiple LLM providers via CLI tools (Claude Code, Codex, Cursor CLI, Aider, OpenCode) and care about both security and cost.

**Secondary.** Product managers and other non-traditional builders who have started using Claude Code or similar tools (the population Anthropic explicitly wants to support) and need a guardrail-shaped product rather than a CLI.

**Tertiary.** Developers in regulated industries (health, finance, legal) where cloud-based key managers are a non-starter and a local, auditable, open-source alternative is required.

**Explicitly not the audience.**

- Enterprise teams with existing secret management infrastructure (Vault, AWS Secrets Manager). They have their solutions.
- Users who only ever use one provider and never look at cost.

## 3. Goals and non-goals

### Goals

1. Make it impossible for an AI coding agent to accidentally see, log, or transmit a real API key during normal operation.
2. Show the user their combined LLM spend across providers in real time, in the menubar, with no setup beyond adding keys.
3. Reduce the time-to-first-secured-key to under 60 seconds for a non-CLI-native user.
4. Provide hard budget caps that the user controls, enforced at the proxy layer.
5. Be open source and auditable. Every byte of key handling must be inspectable.

### Non-goals

- Team or organization-level secret sharing (1Password, Doppler, Infisical own that).
- Cloud sync of keys across devices in v1. Local-only is the security story.
- Generic password management (1Password owns that).
- Replacing provider billing dashboards entirely. We surface and aggregate; we don't replace.
- Becoming an LLM gateway (LiteLLM owns that). We use a minimal proxy as a security mechanism, not as a routing/abstraction layer.

## 4. Solution overview

`shh` is a native macOS menubar app with three components that work together.

### a. The vault

API keys stored in macOS Keychain, gated by Touch ID or password. Per-key metadata: provider, label, scope (which projects/CLIs can use it), monthly budget cap, created date, last used. The vault never exposes raw keys to the UI; it only exposes them to the proxy process via XPC.

### b. The proxy

A local proxy on `127.0.0.1`, started by the menubar app, that AI coding CLIs point to via standard environment variables (e.g. `ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL` — both already supported by the official CLIs).

The CLI sees a dummy bearer token (e.g. `shh-anthropic-default`). The proxy looks up the real key in Keychain, swaps it onto the outbound request, and forwards to the provider. The real key is never written to disk, never printed to stdout, never readable from `/proc`, and never inherited by child processes of the CLI.

### c. The tracker

Every request through the proxy is logged locally (SQLite) with provider, model, input tokens, output tokens, computed cost, and a project tag derived from the working directory of the calling process. Menubar shows live spend; click for breakdowns by provider, model, project, and time window.

## 5. User stories

- *As a developer,* I want to add my Anthropic API key to a vault once, *so that* I never have to put it in a `.env` file or shell config again.
- *As a Claude Code user,* I want my key to be invisible to Claude itself, *so that* a stray `printenv` or a captured stack trace can't leak it to Anthropic's servers as part of my conversation context.
- *As a solo builder,* I want a menubar showing my combined daily and monthly spend across Anthropic, OpenAI, and Gemini, *so that* I notice runaway costs the same day instead of at the end of the month.
- *As a cautious user,* I want to set a $20/day cap on my Opus key, *so that* a runaway agent loop is automatically stopped before it costs me $200.
- *As a PM who just installed Claude Code,* I want to set up secure key handling without writing a wrapper script, *so that* I can use the tool safely without learning shell internals.
- *As an open-source-conscious developer,* I want to read the source code of anything that touches my API keys, *so that* I can trust the product without trusting a company.

## 6. Functional requirements

### 6.1 Vault

- **FR-V1.** Store API keys in macOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` access control.
- **FR-V2.** Reading any stored key must require Touch ID, Apple Watch unlock, or password (LAContext).
- **FR-V3.** Each key must have: provider (enum), display label (string), scope rules (project paths or CLI names), monthly budget cap (decimal, optional), daily budget cap (decimal, optional), created date, last used date.
- **FR-V4.** The UI must never display the full raw key after initial entry. Show provider + last-4 + label only.
- **FR-V5.** Adding a key must support paste from clipboard; the clipboard entry must be cleared after successful save.
- **FR-V6.** Support multiple keys per provider (e.g. personal Anthropic key + work Anthropic key).
- **FR-V7.** Keys must be exportable as a backup, encrypted with a user-provided passphrase. No plaintext export.

### 6.2 Proxy

- **FR-P1.** Run as a separate process (XPC service or LaunchAgent) supervised by the menubar app.
- **FR-P2.** Listen on `127.0.0.1` only — never on a public interface.
- **FR-P3.** Use HTTPS with a self-signed cert installed in the system trust store at first run, with explicit user consent. (Alternative: HTTP on loopback. See open question Q1.)
- **FR-P4.** Support Anthropic, OpenAI, and Google Gemini in v1, using the providers' standard base URLs as upstream targets.
- **FR-P5.** Inbound requests use a dummy token in the format `shh-{provider}-{label-slug}`. The proxy resolves this to a real key via Keychain (which triggers biometric unlock if the cache has expired).
- **FR-P6.** Real keys are held in process memory only for the duration of forwarding (typically <100ms), then zeroed.
- **FR-P7.** Do not log request or response bodies. Log only: timestamp, provider, model, input/output token counts, cost, and project tag.
- **FR-P8.** Enforce daily and monthly budget caps per key. When a cap is reached, return HTTP 429 with a clear error message and a menubar notification.
- **FR-P9.** Add a request-ID header (`X-Shh-Request-Id`) to every forwarded request for traceability in provider-side logs.

### 6.3 Cost tracker

- **FR-C1.** Log every forwarded request to a local SQLite database with: timestamp, provider, model, input_tokens, output_tokens, cost_usd, project_tag, key_id.
- **FR-C2.** Token costs are computed from a bundled, versioned price table. Update the price table from a signed manifest at `github.com/avirumapps/shh-prices` on launch, with a fallback to the bundled version.
- **FR-C3.** Menubar shows today's spend as the default widget.
- **FR-C4.** Click-through shows a panel with today, this week, this month, and all-time spend; breakdown by provider, model, project, and key.
- **FR-C5.** The panel supports filtering by date range and by project.
- **FR-C6.** Optional: pull authoritative spend from provider billing APIs (where read-only key access exists) and reconcile against local logs. Surface any discrepancy.
- **FR-C7.** Spend data must be exportable as CSV.

### 6.4 CLI integration

- **FR-I1.** One-click "Set up Claude Code" action that writes the appropriate `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` values to `~/.zshrc` or `~/.bash_profile` (with user confirmation), or sets them in `~/.claude/settings.json`.
- **FR-I2.** Equivalent one-click setup for Codex, Cursor CLI, Aider, OpenCode, Gemini CLI.
- **FR-I3.** A `shh` CLI with subcommands:
  - `shh run -- <command>` — ad-hoc process-replacement injection
  - `shh status` — connection check
  - `shh spend` — terminal-friendly cost summary
  - `shh keys` — list configured keys (last-4 only)
  - `shh quiet` — temporarily pause logging (for sensitive sessions)
- **FR-I4.** MCP server endpoints exposing read-only spend queries (e.g. *"how much have I spent on Opus this week?"*) so Claude itself can answer cost questions without ever seeing keys.

### 6.5 Security UX

- **FR-S1.** First-run flow explains, in three screens, the threat model: where keys live, why the proxy exists, what happens if you don't use the app.
- **FR-S2.** Touch ID prompts show what is being unlocked and why (*"Claude Code wants to use your Anthropic key"*).
- **FR-S3.** Menubar shows a clear visual indicator when the proxy is running (green dot) and when it's not (gray dot).
- **FR-S4.** Detect when a CLI is configured to use a real key directly (not the proxy) and warn the user.
- **FR-S5.** Scan `~/.zshrc`, `~/.bash_profile`, and common `.env` files at first run for raw API keys and offer to migrate them into the vault.

## 7. Non-functional requirements

### Performance

- Proxy added latency: <10ms p50, <30ms p99, on Apple Silicon.
- Menubar UI: zero perceptible lag on click; spend panel renders in <100ms with 10,000 logged requests.
- Memory: <80MB resident for the menubar app + proxy combined, idle.

### Security

- Keys must never be written to disk in plaintext. Anywhere. Ever.
- Keys must never appear in logs (system, app, or proxy).
- Keys must never appear in crash reports. Crash reporter must scrub anything matching known key patterns (`sk-ant-*`, `sk-proj-*`, `AIzaSy*`).
- The proxy process must use macOS sandbox entitlements scoped to network access only.
- All third-party dependencies must be auditable; no obfuscated binaries.

### Reliability

- Proxy must auto-restart on crash within 2 seconds.
- If the proxy is unreachable, CLI tools must get a clear error pointing to a menubar action, not a generic connection failure.
- App must survive macOS sleep/wake without dropping the proxy.

### Privacy

- No telemetry by default. Optional opt-in error reporting only, with clear scope and retention policy.
- No network calls except: provider APIs (via proxy), price-table updates from GitHub, optional Sparkle update checks.
- All local data (SQLite, Keychain, logs) deletable via a single "Reset" action.

### Compatibility

- macOS 14 (Sonoma) or later. Apple Silicon and Intel.
- Tested with: Claude Code, Codex CLI, Cursor CLI, Aider, OpenCode, Gemini CLI.

## 8. Threat model

This section justifies the product's existence. Each threat below is a real, documented vector that current solutions don't fully address.

| Threat | Mechanism | Mitigation in `shh` |
|---|---|---|
| `.env` file capture | Claude Code reads project `.env` into its context window | Keys never live in `.env`. Setup writes only `ANTHROPIC_BASE_URL` + dummy token. |
| Process env inheritance | Child processes of the CLI inherit `ANTHROPIC_API_KEY` and can leak it | Real key never enters the CLI's process tree. Only dummy token is exported. |
| stdout/stderr capture | Agent runs `printenv`, a stack trace prints the auth header, etc. | Real key never reaches the CLI's stdout. Worst-case leak is the dummy token, which is useless without the proxy. |
| `/proc/{pid}/environ` | Same-user processes can read each other's env vars (Linux) | Same defense: real key only lives in the proxy process, not the CLI's environment. |
| Framework configs on disk | Test runners write resolved config (including secrets) to `.pytest_cache`, `.next/`, etc. | Frameworks resolve to the dummy token, which is the only thing that ever gets written. |
| Shell history | User pastes a key into a `curl` command for debugging | App provides `shh curl` wrapper that uses the proxy. Documentation discourages raw key use. |
| Compromised dependency | An npm/pip package exfiltrates env vars | Same defense as process inheritance: only dummy tokens are in the env. |
| Backup leakage | Time Machine or iCloud backs up plaintext `.env` files | Keychain entries follow standard Apple backup encryption; nothing else to back up. |

### Out of scope (acknowledged)

- Malicious code running as the same user that wants to specifically attack `shh` (e.g. read Keychain via privilege escalation). The user has bigger problems if this happens.
- Compromise of the provider's API itself.
- The user pasting a real key into a chat with Claude (this is a UX/training problem, not a vault problem).

## 9. UX principles

1. **Boring is the goal.** The product should feel like a system utility, not an app. Once configured, the user should forget it exists until the menubar shows a number they don't like.
2. **One-click setup beats infinite configurability.** The default flow must work end-to-end with two clicks: "Add Anthropic key" and "Set up Claude Code."
3. **The threat model is the marketing.** The first-run explanation of why the proxy exists is the most important screen in the app.
4. **Cost transparency builds trust.** Show every cent, in real time, with no telemetry warnings or upsell.
5. **Respect the keyboard.** Every action should have a shortcut. The menubar should be openable with a hotkey.
6. **Live the name.** The product is `shh`. It does not announce itself, it does not nag, it does not ship features that talk over the user. Restraint is the brand.

## 10. Success metrics

### v0.1 (private alpha, weeks 1–4)

- 100 GitHub stars
- 20 active users with at least one key in the vault
- Zero reported key leaks
- Time-to-first-secured-key under 5 minutes (measured via opt-in instrumentation in alpha)

### v1.0 (public launch, month 3)

- 1,000 GitHub stars
- 500 active users
- Hacker News / Show HN front page
- At least one mention in a Claude Code or Cursor blog post or release note
- Time-to-first-secured-key under 60 seconds for non-CLI-native users (measured via in-app onboarding telemetry, opt-in)

### Long-term

- Becomes the default install for any "how to set up Claude Code safely" tutorial
- At least one third-party tool (cmux, Conductor, Superset) integrates the `shh` CLI as a recommended setup step

## 11. Scope

### v0.1 — "It works for me" (2 weekends)

- Menubar app, SwiftUI
- Add/list/delete keys for Anthropic, OpenAI, Gemini
- Keychain storage with biometric unlock
- Local proxy on `127.0.0.1`
- Today's spend in menubar
- Manual setup instructions (no one-click integration yet)
- Open source, MIT, on GitHub

### v0.5 — "Friends and family" (4–6 weeks)

- One-click "Set up Claude Code" action
- Spend breakdown panel (provider, model, project, time)
- Daily and monthly budget caps with 429 enforcement
- Threat-model first-run flow
- Existing-keys scanner and migration helper
- `shh` CLI

### v1.0 — "Show HN" (3 months)

- All providers above plus Cursor, Codex, OpenCode, Aider, Gemini CLI integrations
- MCP server for read-only spend queries
- Provider-billing-API reconciliation
- CSV export
- Auto-update via Sparkle
- Documentation site at `shh.avirumapps.com`
- Threat-model writeup as launch material

### Out of scope for v1.0

- Team / multi-user features
- Cloud sync across devices
- Windows or Linux versions
- Provider routing or fallback (use LiteLLM if you need that)
- Generic password management (use 1Password)

## 12. Risks and open questions

### Risks

- **Anthropic ships built-in secrets management** in Claude Code (per their open issue), which would solve the Anthropic-only case but not the multi-provider case. *Mitigation:* position as multi-provider from day one.
- **Apple ships an OS-level LLM key vault** in a future macOS. *Mitigation:* by then, the cost-tracking and threat-model differentiation should be the moat.
- **Keycard (keycard.studio) launches first** and takes the "AI key vault" mindshare. *Mitigation:* `shh` isn't pitched as a vault — it's pitched as a proxy + cost tracker. Different shape, different demo, different positioning.
- **Self-signed cert in system trust store** is a friction point and a small attack surface. *Alternative:* use a non-HTTPS local proxy (HTTP on loopback is acceptable per most security models). See open question Q1.
- **Some CLIs may not honour their `*_BASE_URL` env vars correctly**, or only honour them for some endpoints. Requires per-CLI testing.
- **Cursor's hosted mode** (where Cursor's own server makes the API call) cannot be proxied. We can only support Cursor's BYOK CLI mode. Document clearly.

### Open questions

- **Q1.** HTTPS with installed cert vs. plain HTTP on loopback — which is the better tradeoff between security and friction?
- **Q2.** Should the app support proxying tool-use / MCP requests too, or only model inference? (Probably yes, but adds complexity.)
- **Q3.** How do we handle streaming responses while still capturing accurate token counts? (Probably parse SSE chunks server-side.)
- **Q4.** Should we offer a "shadow mode" that observes existing key usage without proxying, just to give users the cost dashboard before they commit to migration?
- **Q5.** License: MIT, Apache 2, or AGPL? (cmux uses AGPL specifically to prevent closed-source forks. Worth considering.)

## 13. Competitive landscape

| Tool | Vault? | Proxy? | Cost tracking? | Local? | OSS? |
|---|---|---|---|---|---|
| 1Password CLI (`op run`) | Yes | No | No | Hybrid | No |
| Doppler | Yes | No | No | No | No |
| Infisical | Yes | No | No | Hybrid | Partial |
| Keycard (keycard.studio) | Yes | No | No | Yes | MIT |
| VaultProof | Yes | Yes | No | No | Partial |
| LLMeter | No | No | Yes | Hybrid | Yes |
| AI Cost Bar | No | No | Calc only | Yes | No |
| LLM Ops / Cloudidr | No | Yes (cloud) | Yes | No | No |
| LiteLLM | No | Yes | Yes | Yes (self-host) | Yes |
| Apple Keychain | Yes | No | No | Yes | N/A |
| **`shh` (proposed)** | **Yes** | **Yes** | **Yes** | **Yes** | **Yes** |

---

# Part 2 — How to build it

`shh` is a **native macOS app that lives on GitHub.** Those aren't opposites; they're the same thing.

## Two separate decisions, often conflated

**Decision 1: What is the product?**
A native macOS app (SwiftUI menubar + local proxy + Keychain integration). This doesn't change. The whole thesis depends on it being native, local, and Mac-shaped. A web service or a CLI-only tool doesn't solve the problem.

**Decision 2: Where does it live and how do people get it?**
GitHub repo, distributed via Homebrew cask and direct DMG download. Source is open. Binary is signed and notarized. Anyone can audit, fork, or build from source.

These are independent choices. The product is a Mac app. The distribution and trust model is GitHub-and-Homebrew.

## Why GitHub-as-distribution, not the Mac App Store

For this specific product, the App Store is actively wrong:

1. **Sandboxing kills the proxy.** App Store apps can't easily run a local network proxy that other tools route through. This is the entire product.
2. **Trust requires source visibility.** Nobody gives their API keys to a closed-source binary. The whole pitch is *"you can read every line that touches your keys."*
3. **App Store review cycles will kill iteration speed.** You need to ship fixes daily in early weeks. App Store review is 1–7 days per release.
4. **Apple takes 30%.** Irrelevant for a free product, but relevant if you ever want to monetize a Pro tier.
5. **The audience doesn't shop in the App Store for devtools.** Developers install via Homebrew (`brew install --cask shh`) or by downloading a DMG from GitHub. cmux, Ghostty, Rectangle, Maccy, Stats — none are in the App Store.

The right pattern is **what cmux and Ghostty actually do**:

- Source code on GitHub (open source license)
- Built artifacts (signed, notarized DMG) attached to GitHub Releases
- Homebrew cask in your own tap (`brew tap avirumapps/shh && brew install --cask shh`)
- Auto-updates via Sparkle, with the update feed pointing back to GitHub Releases
- Documentation site at `shh.avirumapps.com` that's mostly a pretty wrapper around the README

## Recommended tech stack

The product has three components with very different requirements. Each one points to a clear technology choice; the overall stack is defined by minimizing dependencies and using Apple's own tools where they're best.

### Stack summary

| Layer | Choice | Why |
|---|---|---|
| App framework | SwiftUI 6 + AppKit interop | Native menubar, native Keychain, native Touch ID |
| Language | Swift 6 | One language across app, proxy, CLI |
| Proxy | SwiftNIO in XPC service | Fast, sandboxable, process-isolated |
| Storage | SQLite via GRDB | Right-sized, reliable, type-safe |
| CLI | swift-argument-parser | Shares types with the app |
| Crypto | macOS Security.framework | Use Apple's primitives, not roll-your-own |
| Auth | LAContext (Touch ID) | One-liner, OS-grade |
| Updates | Sparkle 2 | Standard for indie Mac apps |
| Build | Xcode 16 + GitHub Actions | Standard CI pipeline |
| Distribution | Homebrew cask + GitHub Releases | What this audience expects |
| Min macOS | 14 (Sonoma) | Covers ~85% of Mac users; lets you use modern SwiftUI |

### The vault and menubar app — Swift 6 + SwiftUI 6 + AppKit interop

Non-negotiable for this product. Native Keychain access, native Touch ID via `LAContext`, native menubar via `MenuBarExtra` — none of these work cleanly in Electron, Tauri, or Flutter. A 200ms launch and 30MB resident is achievable in Swift; an Electron equivalent starts at 150MB and 800ms.

Specifically use `MenuBarExtra` with `.window` style, the `@Observable` macro for state, `SecItemAdd` / `SecItemCopyMatching` for Keychain, and `LAContext` for biometrics.

### The proxy — SwiftNIO in a separate XPC service

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| SwiftNIO in same process as menubar app | Simplest to ship | Crash in proxy = crash in menubar; harder to isolate | No |
| **SwiftNIO in separate XPC service** | Process isolation, auto-restart by launchd, sandboxable separately | Slightly more architecture upfront | **Yes** |
| Embed Caddy/Mitmproxy/local LiteLLM | "Free" feature set | External binary, harder to sign, dependency hell | No |

SwiftNIO is what every serious Mac proxy uses (Proxyman, Rockxy, Proxygen). Apple's own non-blocking I/O framework, blazingly fast, integrates cleanly with the rest of the Swift ecosystem.

The XPC architecture also gives you a real security story: the proxy process can be sandboxed with only network entitlements (no filesystem, no Keychain, no UI), and it talks to the main app via a typed XPC interface. The main app holds the Keychain access; the proxy asks for keys on demand. This is defense-in-depth, not a marketing claim.

### The CLI (`shh run`, `shh status`, `shh spend`) — swift-argument-parser

Apple's official CLI library. A few hundred lines for what you need, integrates natively with the rest of the Swift code, produces a small static binary. Bundle it inside the .app and symlink it into `/usr/local/bin/shh` during install (with user permission).

Don't reach for Rust, Go, or Python. You already have the Swift codebase; sharing types between the CLI and the menubar app is much cleaner than re-implementing them in another language.

### Storage — SQLite via GRDB

GRDB is the canonical Swift SQLite library. Type-safe queries, migrations, change observation. SQLite itself is bulletproof for "log every request" — thousands of writes per second on commodity hardware, file-format forwards-compatible forever.

One database file at `~/Library/Application Support/shh/log.sqlite`. Backups are a single file copy. Don't use Core Data (overkill, worse DX) or Realm (extra dependency, sync features you don't need).

### Cost calculation — bundled JSON + signed manifest from GitHub

Bundle a known-good price table with each release. On launch, fetch a signed manifest from `raw.githubusercontent.com/avirumapps/shh-prices/main/prices.json`. If the fetch succeeds and the signature verifies, use the live one; otherwise fall back to bundled. Same pattern Sparkle uses for updates.

### Auto-updates — Sparkle 2.x

The de facto standard for non-App-Store Mac apps. Supports EdDSA-signed updates, delta updates, and integrates cleanly with GitHub Releases. cmux uses it. Ghostty uses it. Don't reinvent this.

### Build, sign, notarize, distribute

- **Xcode 16+** for the project
- **xcodebuild + xcrun notarytool** in GitHub Actions for CI builds
- **Apple Developer ID Application certificate** ($99/year) stored as a GitHub Action secret
- **DMG packaging** via `create-dmg`
- **GitHub Releases** as the distribution channel — every tag triggers a build, signs, notarizes, packages, and uploads
- **Homebrew tap** in a separate repo (`avirumapps/homebrew-shh`) with a cask formula that points at the GitHub Releases URL

### What to explicitly *not* use

- **Electron / Tauri** — wrong category for this product. Trust collapses immediately.
- **Flutter** — macOS support improving but not Touch-ID-grade. Wrong audience.
- **Catalyst** — designed for porting iPad apps. Not what you're doing.
- **React Native for macOS** — no compelling reason; native is the whole point.
- **Rust** — tempting for the proxy, but Swift+SwiftNIO is just as fast for this workload, and keeping one language is a huge win for solo development.

## What "open source GitHub project" usually means and why it's the wrong frame

When people say "build it as an open source GitHub project," they usually mean one of two things, both of which would be wrong here.

**Wrong frame 1: "Just publish source code, don't worry about the app polish."** This kills the product. Your wedge against 1Password CLI is specifically that it's a polished Mac app a non-engineer can install in 60 seconds. If your repo's README starts with `git clone && xcodebuild`, you've lost the audience that matters most.

**Wrong frame 2: "Build a CLI or library, not a GUI app."** Same problem. The threat model requires a long-running supervised process and a menubar status indicator. A pure CLI is `op-env` reborn — useful, but not the wedge.

The right frame: **a polished native Mac app, distributed and trust-modeled like a serious open source project.**

## What this looks like concretely

Your GitHub repo on launch day has:

- `README.md` — the marketing site (demo GIF, threat model, comparison table, install instructions)
- `INSTALL.md` — three install paths: Homebrew (one line), DMG download (one click), build from source (for the auditors)
- `THREAT_MODEL.md` — the standalone document; this is also your launch material
- `BUILD_LOG.md` — the dev journal
- `LICENSE` — your license decision (MIT/Apache/AGPL)
- `SECURITY.md` — how to report a vulnerability
- `Shh.xcodeproj/` — the actual Swift code
- `Releases/` (via GitHub Releases, not committed) — signed notarized DMGs

A first-time visitor sees: a beautiful demo GIF, a one-line install command, a threat model that explains why the product exists, and an audit trail of your engineering decisions. That's what builds trust faster than any social post.

## The trust loop

The mental model the audience runs when they land on the repo:

> *"I'm about to give this app my Anthropic key. Can I trust it? Let me check: is the source open? Yes. Is it signed and notarized? Yes. Does the README explain what touches my key? Yes. Are there other people using it? Looks like 200 stars and 15 contributors. Does the dev seem serious? Build log goes back 3 months, decisions are explained, security policy exists. OK, I'll install it."*

Every check fails if you ship "just an open source project" without app polish. Every check fails if you ship a polished Mac app without the source. **The combination is the product.**

## What you actually do differently from "just a GitHub project"

1. **Treat the Xcode project and the GitHub repo as one artifact.** Same root, same versioning, same release process. `git tag v0.1.0` triggers a CI build that produces a signed DMG and uploads it to GitHub Releases.
2. **Set up an Apple Developer account ($99/year) for code signing and notarization.** Without it, macOS Gatekeeper warns users on first launch and you'll lose 80% of installs at that screen.
3. **Maintain a Homebrew tap from day one.** `homebrew-shh` repo with a cask formula that points at your GitHub Releases. One-line install is non-negotiable for this audience.

That's the entire delta from "just a GitHub project" to "a real indie Mac app distributed via GitHub." A few days of CI setup, ~$100/year, and a discipline of cutting clean releases.

---

# Part 3 — How to launch and find traction

Honest opener: **distribution-free product launches almost always fail, and the ones that look like they didn't usually had hidden distribution.** Mitchell Hashimoto had years of HashiCorp credibility before Ghostty. cmux's creators were already in the AI dev community. Plan around that reality.

That said, `shh` has unusually good organic potential because it sits at the intersection of three actively-discussed topics (AI coding agents, API costs, prompt injection security).

## How distribution actually works for this kind of product

There are really only three mechanisms that produce organic traction for a developer tool with no marketing:

1. **Inclusion in someone else's content** — a tutorial, a comparison post, a "how I set up X" writeup
2. **Solving a problem someone is actively complaining about** — you show up in a thread where the pain is being discussed
3. **Being the answer to a search someone is already doing** — long-tail SEO from the documentation itself

Almost every "organic" indie launch is one of these three, dressed up as something else.

## The single best launch channel for `shh`

**The two open Anthropic GitHub issues:**

- `claude-code` issue **#29910** (built-in secrets management request)
- `claude-code` issue **#23642** (`op://` reference support)

These are the highest-signal channels you have, and almost nobody thinks of GitHub issues as a launch channel. Why they're perfect:

- The people commenting on those issues are *exactly* your target users.
- A comment that says "I built this to solve exactly this — it's open source, here's the link" is on-topic, not spam.
- Anthropic engineers read their own issues. They may link to `shh` from the issue when they close it ("for now, users can try X"), which is the highest-quality endorsement you can get.
- Watchers of those issues get email notifications when you comment. You're piggybacking on Anthropic's notification infrastructure.

This is your single highest-leverage move. Do this on day one.

## The ranked list of everything else

### Tier 1 — Do these

**1. Hacker News Show HN, posted at 8–10am ET on a Tuesday or Wednesday.** Title format: *"Show HN: shh – Local API key vault and cost tracker for Claude Code."* HN's audience is exactly right (security-conscious devs, indie hackers, AI tool users). The post needs three things: a clear one-liner, a working demo (screen recording, GIF in the README), and you actively replying to every comment for the first 4 hours. A successful Show HN does 200–2000 GitHub stars in 48 hours. Downside: it's a coin flip. Maybe 1 in 5 well-built tools hit the front page.

**2. Reddit `r/ClaudeAI` and `r/cursor`.** A post titled *"I built a local key vault + cost tracker for Claude Code because I got tired of the .env file problem"* lands well there. `r/ClaudeAI` especially — every member is your target user. Don't post to both at the same time; space by a week.

**3. The README is your marketing.** Most successful indie devtools are discovered via Google searches like *"claude code api key security"* or *"track openai spend mac."* If your README has clear H2s for those exact phrases, you'll show up in search within 2–4 weeks. Spend more time on the README than on any social post. Include: the threat-model section as a standalone narrative, a clean GIF demo, and the comparison table from the PRD.

### Tier 2 — Worth doing if you have an hour each

**4. Submit to `awesome-claude-code`, `awesome-mcp`, `awesome-macos`.** These curated lists are how a lot of devs discover tools. PRs get accepted readily for genuinely useful, well-documented tools.

**5. Comment on Patrick D'Appollonio's blog post** and Filip Hric's `.env` post. They write about exactly your problem. A thoughtful comment with a link is on-topic.

**6. Submit to Product Hunt — but only on day 30, not day 1.** PH has become a checklist item rather than a real channel for developer tools, but it does drive a small amount of traffic and lets you say "Featured on Product Hunt" forever. Wait until you have HN/Reddit-driven users so you have early reviews.

**7. Post in the Anthropic Discord, the Cursor Discord, and the Claude Code Discord.** Find the relevant channel (usually `#show-and-tell` or `#tools`). Post once, don't repost.

### Tier 3 — Don't bother

- **Twitter/X without an existing audience.** With zero followers, your tweet gets seen by ~12 people.
- **LinkedIn.** Wrong audience for a CLI-adjacent dev tool.
- **Indie Hackers, BetaList, Hacker Noon, Dev.to.** These were good 2017–2020. Now they mostly drive low-quality traffic.
- **Writing your own blog post on a fresh domain.** Will be read by your launch traffic and then nothing. Put that energy into the README instead.

## The actual sequence — a 7-day launch window

| Day | Action |
|---|---|
| **Day 0** | README polished. Demo GIF in the first 200 pixels. Threat model as a section. Comparison table. Working install instructions. Tag `v0.1.0` release on GitHub. |
| **Day 1, morning** | Comment on Anthropic GitHub issues #29910 and #23642. Respectful, on-topic, link to repo. *"I built this because I was frustrated with the same thing — open source, here's the link, would love feedback."* |
| **Day 1, afternoon** | Post in Anthropic Discord `#show-and-tell`, Cursor Discord, Claude Code Discord. |
| **Day 2 (Tue or Wed AM)** | Show HN. Stay at your desk for the next 4 hours and reply to every comment with substance. |
| **Day 3–4** | Post to `r/ClaudeAI`. Whether or not HN went well, this is a different audience and a different signal. |
| **Day 5** | Submit PRs to 2–3 awesome-lists. Comment on relevant blog posts. |
| **Day 6–7** | Quiet. Read every issue, respond to every PR, ship a 0.1.1 with the most-requested fix. |
| **Day 30** | Product Hunt launch with whatever momentum you've built. |

## What success and failure look like

**A good launch** for `shh` nets you 500–2000 GitHub stars in the first month, 20–100 active users, and 1–3 inbound conversations from someone interesting (Anthropic engineer, another tool maker, a podcaster). That's the realistic ceiling for an indie launch with no audience.

**A failed launch** nets you 50–150 stars and silence. This happens to most launches and is fine — you ship 0.2 with the lessons, post again in 3 months, and the second wave often does better than the first.

The thing that determines which side you land on is almost always the README and the demo GIF, not the channel choice. **A great product with a great README will succeed on any channel above. A mediocre product with a mediocre README will fail on all of them.**

## The one piece of distribution you can build now, while building the product

Start a `BUILD_LOG.md` in the repo from week one. A dated dev journal — what you tried, what worked, what didn't, what you decided. This costs you 10 minutes a day and gives you three things at launch:

1. A track record that makes the project look serious to skeptical visitors.
2. Material to reference in HN comments (*"I tried X first; it didn't work because…"*).
3. SEO. A repo with months of dated, technical, narrative content ranks better than one with just a README.

That's the closest thing to "building distribution before launch" that's actually achievable for a solo indie dev with no time. It's free, it compounds, and it's been the secret weapon for every successful indie devtool I can think of.

---

# Part 4 — UI design

## Aesthetic direction

The reference points from this conversation — Ghostty, cmux, Maccy, Stats — share a single sensibility: **system-utility refinement**. They feel like things Apple should have shipped but didn't. They lean on monospace, tabular numbers, near-black surfaces, generous negative space, and zero decorative chrome. The product is the data; the chrome gets out of the way.

For `shh` specifically, three additional pressures shape the design:

1. **It's a security utility.** Calm beats clever. No animations on the menubar. No celebratory confetti when you add a key. The product should feel like the lock on your front door — present, reliable, never demanding attention.
2. **The number is the marketing.** The menubar dollar amount is the most important pixel in the whole product. Every UI decision serves making that number readable and trustworthy.
3. **The audience self-selects on craft.** The people who care about API key security are the same people who notice 1px misalignments. Polish is non-negotiable.

The one-line positioning of the design: **"The menubar is the product. Everything else is plumbing."**

This is doubly true for `shh` — the name itself demands restraint. A product called `shh` cannot have an UI that talks over the user.

## Design tokens

| Token | Value | Use |
|---|---|---|
| `--surface-base` | `#FAFAF8` | App window background (warm off-white) |
| `--surface-menubar` | `rgba(28,28,30,0.96)` | Menubar dropdown (system dark) |
| `--surface-card` | `#FFFFFF` | Inset cards inside windows |
| `--ink` | `#1A1A1A` | Primary text |
| `--ink-muted` | `rgba(0,0,0,0.55)` | Secondary text |
| `--ink-faint` | `rgba(0,0,0,0.4)` | Labels, hints |
| `--accent` | `#082D35` | Primary brand (dark teal) |
| `--accent-action` | `#082D35` | Filled buttons, active tabs |
| `--state-active` | `#1D9E75` | Live activity, success, "request in flight" |
| `--state-warn` | `#BD8F1E` | Approaching budget cap |
| `--state-error` | `#FF5A5A` | Proxy down, hard failure |
| `--border-hairline` | `rgba(0,0,0,0.08)` | Default borders (0.5px) |
| `--font-sans` | SF Pro Text | UI |
| `--font-mono` | SF Mono | Numbers, keys, paths, shortcuts |
| `--font-display` | SF Pro Display, weight 200–300 | The hero spend number |

## Type system

Three sizes, two weights, period.

| Role | Size | Weight | Notes |
|---|---|---|---|
| Hero number | 32–44px | 200–300 (light) | Tabular numerals always (`font-feature-settings: 'tnum'`) |
| Section title | 15–18px | 500 | Sentence case, never title case |
| Body | 13px | 400 | Default reading size |
| Label | 11px | 500 | Uppercase, +0.04em letter-spacing, used sparingly |
| Mono | 12px | 400 | Numbers, env-var names, file paths, keys |

Light weight on the hero number does the heavy lifting. It's what makes the spend feel calm rather than alarming, and it's what most utility apps get wrong by reaching for bold.

## Surface hierarchy

`shh` has exactly five surfaces. They earn their existence; nothing else should be added without justification.

1. **Menubar icon** — the always-visible surface. A lock glyph + dollar amount.
2. **Menubar dropdown** — the primary surface. ~95% of users will live here.
3. **Dashboard window** (⌘D) — the click-through dopamine hit.
4. **Connect a tool** sheet (⌘T) — the integration moment.
5. **Add key** sheet (⌘N) — the trust moment.

That's it. No settings page in v1 (move to ⌘,, but keep it brutally short). No onboarding wizard beyond the first-run threat-model screens. No analytics views. No "tips & tricks." Every additional surface is debt.

## The five surfaces, in detail

### 1. Menubar icon

A 16×16 lock glyph paired with the current daily spend in tabular monospace. Four states:

- **Idle** — white lock, white number. The default 99% of the time.
- **Active** — teal lock, teal number. A request is in flight; the color persists for ~400ms after completion so brief activity is visible.
- **Approaching cap** — amber lock, amber number. Triggered at ≥80% of any daily cap on any active key.
- **Proxy down** — red broken-lock glyph, "offline" label. Tools using the proxy will fail safely; this state demands the user's attention.

Crucially, **the number is the affordance**. There's no separate icon-with-tooltip. The number itself communicates state, status, and identity simultaneously.

### 2. Menubar dropdown (320×420)

The information hierarchy, top to bottom:

1. **Header strip** — "Today" label and proxy-status pill (green dot + "Proxy running" / red dot + "Proxy down")
2. **Hero number** — today's spend in light 32px, with a one-line context: "$87.40 this month · cap $250"
3. **Providers** — three rows in monospace, one per provider: `A  anthropic  $3.12`. Single-letter prefix is the visual shorthand; the full name reassures.
4. **Active session** — what's currently spending money, in monospace: `claude-code · avirumapps  $0.34 ↑`. The teal arrow indicates a live request. Disappears when nothing's active.
5. **Actions** — four rows with keyboard shortcuts on the right: Open dashboard (⌘D), Add key (⌘N), Connect a tool (⌘T), Settings (⌘,). The first action is the default and visually distinguished by a faint background.

Dense but not cluttered — every line earns its existence and there's a visible separator (0.5px hairline) between sections. No scrolling. If the content doesn't fit, it doesn't belong here.

### 3. Dashboard window

Ranged time toggle at top (Today / Week / Month / All time, pill-shaped, teal active). Hero number in 44px light, with a delta annotation showing the most recent change.

A 19-bar sparkline showing hourly spend. The most recent two completed bars are teal (matching the "active" state in the menubar); historical bars are dark teal; future bars are faint. This single visual element does the work of three separate charts in less polished tools.

Below: a per-project breakdown in monospace. Three columns — project name (with a 3px progress bar showing relative spend), CLI used, dollar amount. No filters in v1; the time toggle handles all the filtering anyone needs.

The window is intentionally narrow (640px) — wider would invite more columns, more chart types, more dashboard creep. This is a focused tool, not Datadog.

### 4. Connect a tool

A list of detected AI tools, one row each. Each row shows: a 28px square monogram (the tool's identity at a glance), the tool name, a current-state line in monospace ("Connected · 14 sessions today" or "Detected · not connected" or "Not detected · install first"), and a single primary action.

This is **detection-first, not configuration-first**. The user doesn't configure tools; the app detects them and offers one-button connection. The button's label changes based on state — "Connect", "Manage", or a doc link if the tool isn't even installed.

A footer callout in dark-teal explains what "connect" actually means in plain English: writing one env var to your shell config, with a diff preview. This is the kind of transparency that builds trust with the security-conscious audience.

### 5. Add key sheet

Four fields, in order: Provider (segmented control, three options), Label (text), API key (text, masked after entry), Daily cap (optional, monospace number).

Two trust signals built in:
- A live validation indicator under the API key field — green dot + "Validated · clipboard cleared on save" — that confirms two things at once: the key works, and the app cleaned up after itself.
- The daily cap is **optional but pre-filled with $20** — a sensible default that nudges toward setting some limit without forcing it.

Two buttons: Cancel (outlined) and Save to vault (filled dark teal). No third "advanced options" button. Anything more advanced lives in Settings.

### Touch ID prompt

This is the single moment where the product's value is made visceral. The prompt explicitly names:

- **What is requesting access**: "Claude Code wants to use your"
- **Which specific key**: "Anthropic · personal" in bold
- **How to authorize**: Touch ID glyph and "Touch ID to continue"
- **The fallback**: "Use password…" as a secondary path

This is the screen that converts users from "interested" to "trusting." It must look indistinguishable from a system dialog — no custom branding, no marketing copy, no "Powered by shh" footer. The product disappears into the OS, which is exactly how a security utility should behave.

## Motion

Almost none. Specifically:

- **Menubar icon color transitions**: 200ms ease, on state change only.
- **Dropdown opening**: native macOS menubar animation, no override.
- **Active-request indicator**: the teal color holds for 400ms after a request completes, then fades over 300ms. This is the only "motion" in the product.
- **Bar chart**: bars appear in their final position. No animated growth-from-zero. We're showing data, not performing it.
- **Touch ID success**: native macOS animation, no override.

No springs. No staggered reveals. No micro-interactions on hover beyond a 1-tone background change. The product is calm because that's what trustworthy security tools feel like.

## What we explicitly avoid

- **Gradients of any kind.** Flat fills only. Gradients on a security product read as marketing-driven, which erodes trust.
- **Drop shadows on cards.** Use 0.5px hairlines instead. Shadows imply layered depth that doesn't exist in a system utility.
- **Icons for their own sake.** The only icons in the product are the lock glyph (menubar) and tool monograms (Connect sheet). No icon next to every menu item.
- **Color as decoration.** Color encodes state: teal = active/success, amber = warning, red = error, dark teal = brand/primary action. That's it.
- **Onboarding tours.** First-run is three threat-model screens explaining why the product exists, then drop the user at "Add your first key." No coachmarks, no popovers, no "did you know."
- **Emoji.** Anywhere.
- **Pluralization gymnastics.** "1 key" not "1 key(s)". "14 sessions today" not "14 session(s) today." Either write the conditional logic or rephrase to avoid it.
- **The product talking about itself.** A product called `shh` does not pop a "you've now used `shh` for 30 days!" toast. Not ever.

## Implementation notes for SwiftUI

A few specifics that will save you time when building:

- The menubar icon should be a `MenuBarExtra` with `.menuBarExtraStyle(.window)` for the dropdown — gives you full SwiftUI control instead of NSMenu's limitations.
- For tabular numerals on the spend numbers, use `.monospacedDigit()` modifier — works on any `Text` view.
- The hero number's light weight (200) requires using `Font.system(size: 32, weight: .ultraLight, design: .default)`. SwiftUI's `.title` and `.largeTitle` don't go light enough.
- The 0.5px hairlines need `.frame(height: 0.5)` and `Color.black.opacity(0.08)`. Note: SwiftUI rounds to pixel boundaries, so on non-Retina displays the hairlines render at 1px. That's fine.
- The dashboard window should use `Window` (not `WindowGroup`) since you only ever want one instance, and `.windowResizability(.contentSize)` to lock it to the design dimensions.
- Touch ID is `LAContext().evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, ...)`. The reason string is what shows up in the prompt — keep it identical to the design above.
- For the active-request color persistence, a small `@State` timer with a `withAnimation` wrapper handles the fade cleanly.

---

## Appendix — Decision summary

If you remember nothing else from this document:

- **Name:** `shh` (lowercase, monospace). Tagline: *Your AI keys never speak above a whisper.*
- **Home:** `shh.avirumapps.com`
- **Product:** native macOS menubar app, local proxy, Keychain-backed vault, real-time cost tracker
- **Wedge:** vault + proxy + cost tracker in one product, with non-engineer-grade onboarding
- **Defense:** real keys never enter the AI tool's process tree, stdout, or disk-written configs
- **Stack:** Swift 6 + SwiftUI 6 + SwiftNIO (proxy in XPC service) + GRDB/SQLite + Sparkle
- **Distribution:** GitHub repo + Homebrew cask + signed/notarized DMG (not the App Store)
- **Trust:** open source, auditable, biometric-gated, zero telemetry by default
- **Launch:** Anthropic GitHub issues (Day 1) → Show HN (Day 2) → r/ClaudeAI (Day 3–4) → awesome-lists (Day 5) → Product Hunt (Day 30)
- **Pre-launch moat:** `BUILD_LOG.md` from week one
- **Cost of doing it right:** $99/year Apple Developer account, a few days of CI setup, 10 minutes/day on the build log
- **Design:** five surfaces only (menubar icon, dropdown, dashboard, connect, add key). The menubar number is the product. Calm beats clever. SF Mono for numbers, ultra-light for the hero, dark teal as the only brand color. The product is named `shh` — it must never talk over the user.
