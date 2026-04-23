# shh — Implementation plan (v0.1)

Source: `spec.md` + `research.md`. Target: Mac-native menubar app (SwiftUI + SwiftNIO in XPC + GRDB + LAContext + Keychain) distributed via GitHub Releases + Homebrew cask, open source.

## v0.1 scope

**In:**
- Menubar app with MenuBarExtra
- Keychain vault with LAContext biometric gating
- Scanner + migration flow (Tier 1-3 keys)
- Project-scoped key routing (primary + optional secondary, user-configurable fallback)
- HTTP loopback proxy (SwiftNIO in XPC) for Anthropic / OpenAI / Gemini
- Cost tracker (SQLite via GRDB) with 4D token fields and bundled price table
- 5 CLI connect flows: Claude Code, Codex, Aider, OpenCode, Gemini CLI
- `shh` CLI (swift-argument-parser) with run/status/spend/keys/quiet subcommands
- Dashboard window per §4 design
- First-run threat-model flow (3 screens)
- DMG + notarization + GitHub Releases CI
- Homebrew cask in a tap
- Sparkle 2 auto-update

**Out, explicitly:**
- Cursor integration (cursor-agent not proxyable — Q6 + research §1)
- MCP server for spend queries (cut — Q8)
- Shadow mode (cut — scanner+migration is the low-friction onboarding — Q9)
- Provider billing-API reconciliation (org-admin-only for most providers — research §5)
- Budget caps (defer to v0.5 — cap-atomicity work requires thought)
- Cloud sync across devices
- Windows / Linux
- HTTPS proxy mode (defer unless a CLI forces it)

---

## Phases

### Phase 0 — Bootstrap
**Files:**
- `Shh.xcodeproj` with three targets: `Shh` (menubar app), `ShhProxy` (XPC service), `shh-cli` (Swift package using swift-argument-parser)
- `github.com/avirum-llc/shh` repo — MIT license (default per PRD; confirm with Manish), `.gitignore`, `README.md` placeholder, `SECURITY.md`, `LICENSE`
- `.github/workflows/release.yml` skeleton (don't wire signing yet)
- Bundle ID: `com.avirumapps.shh`
- XPC service bundle ID: `com.avirumapps.shh-proxy`
- LaunchAgent label: same

**Verification:** Blank Xcode project builds all three targets; `xcodebuild archive` runs clean; repo pushes; CI runs on a test tag and produces an unsigned artifact.

**Risk / reversibility:** Bundle IDs and launchd label are one-way doors once users install. Confirm before shipping.

---

### Phase 1 — Vault + MenuBarExtra shell
**Files:**
- `Shh/Services/KeychainStore.swift` — `kSecAttrAccessControl` with `.biometryCurrentSet`; LAContext with `touchIDAuthenticationAllowableReuseDuration = 300`; passed via `kSecUseAuthenticationContext`
- `Shh/Models/VaultKey.swift` — `{id, provider, label, bucket (personal|work), fingerprint (last-4), createdAt, lastUsedAt}`
- `Shh/Models/Vault.swift` — `@Observable`, list of `VaultKey`, CRUD via `KeychainStore`
- `Shh/Views/MenuBarRoot.swift` — `MenuBarExtra(style: .window)` with [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) for programmatic dismiss
- `Shh/Views/MenuBarDropdown.swift` — 320×420, per §4 design (header / hero / providers / actions); today's spend is $0 until Phase 4
- `Shh/Views/AddKeySheet.swift` — four fields per design; clipboard-clear on save
- `Shh/Views/TouchIDPrompt.swift` — reason-string text matches design
- `Shh/App.swift` — `NSApplication.ActivationPolicy.accessory`

**Verification (real Touch ID):**
1. Add key → Touch ID prompt → key in login Keychain with biometric access (confirm via `security dump-keychain`).
2. Lock screen → unlock → read key → Touch ID prompt → returns data.
3. Read second key within 5min → no prompt (LAContext reuse works).
4. Relaunch app → keys persist.
5. Delete a key → gone from Keychain.

**Risk:** LAContext behavior differs on Intel Macs (Touch Bar absent). Test both Apple Silicon and Intel.

---

### Phase 2 — Scanner + migration flow
**Files:**
- `Resources/scanner-patterns.v1.json` — versioned catalog from research §2 (provider / tier / regex / env-hints / notes)
- `Shh/Scanner/PatternCatalog.swift` — loads + validates JSON
- `Shh/Scanner/FileScan.swift` — glob scan paths:
  - Shell configs: `~/.zshrc`, `~/.zprofile`, `~/.bash_profile`, `~/.bashrc`, `~/.profile`
  - .env files: `~/Documents/**/.env`, `~/Documents/**/.env.*`, `~/code/**/.env*` (configurable roots)
  - CLI configs: `~/.claude/settings.json`, `~/.codex/config.toml`, `~/.aider.conf.yml`, `~/.config/opencode/**`, `~/.gemini/**`
  - Shell history: `~/.zsh_history`, `~/.bash_history`
- `Shh/Scanner/TwoSignalClassifier.swift` — regex hit + env/config context; outputs `Detection{path, line, provider, confidence}`
- `Shh/Views/ScanResultsSheet.swift` — list per-detection with "Migrate" / "Skip" / "Ignore forever"
- `Shh/Scanner/Migrator.swift` — read key into vault, then rewrite source file: for `.env` lines, replace value with comment `# migrated to shh on <date>`; for shell exports, comment the line
- `Shh/Scanner/UndoMigration.swift` — keep original value in vault's "migrations" metadata; "Undo" restores the source

**Verification:**
1. Seed a fresh `.env` with Anthropic + OpenAI + Stripe keys; scan → 3 detections, correct tier.
2. Migrate all 3 → keys in Keychain, `.env` rewritten, tests still parse the `.env` without errors (since the key lines are commented, not deleted).
3. Undo one migration → key removed from Keychain, `.env` restored to original.
4. Run scan twice → already-migrated keys are not re-detected (idempotence).
5. Seed a `.zshrc` with an `export ANTHROPIC_API_KEY=sk-ant-...` → scan detects, migrates, replaces with comment + a `# shh: key migrated`.

**Risk:** False positives on ambiguous patterns (Together/Mistral/Cohere with no prefix). Two-signal classifier requires env-var name match for those; write tests with realistic `.env` files.

---

### Phase 3 — Proxy skeleton (SwiftNIO in XPC)
**Files:**
- `ShhProxy/main.swift` — XPC listener delegate + SwiftNIO `ServerBootstrap` on `127.0.0.1:18888`
- `ShhProxy/Router.swift` — path-prefix routing: `/v1/messages` → Anthropic, `/v1/chat/completions` + `/v1/responses` → OpenAI, `/v1beta/models/*:streamGenerateContent` + `/v1/models/*:generateContent` → Gemini
- `ShhProxy/TokenResolver.swift` — parse dummy token format `shh-{provider}-{project}-{key-slug}`; query main app via XPC for `KeychainStore.read`
- `ShhProxy/Forwarder.swift` — AsyncHTTPClient streaming forwarder; rewrite `Authorization` header per provider (`Bearer` for Anthropic, `Bearer` for OpenAI, query param `?key=` or header `x-goog-api-key` for Gemini)
- `ShhProxy/XPCInterface.swift` — protocol shared between main app and service
- `Shh/Services/ProxyXPCClient.swift` — main-app side
- `Shh/Services/LaunchAgentInstaller.swift` — writes `~/Library/LaunchAgents/com.avirumapps.shh-proxy.plist` with `KeepAlive=true`, `MachServices`
- `Shh/Services/ProjectRegistry.swift` — `{token → (project, provider, key-id, fallback-policy)}` map, persisted to `~/Library/Application Support/shh/projects.json`

**Dummy token format:** `shh-<provider>-<project-slug>-<key-slug>` (e.g. `shh-anthropic-avirumapps-personal`). Pinned for v1.

**Verification:**
1. Start proxy via XPC. `curl http://127.0.0.1:18888/v1/messages -H 'Authorization: Bearer shh-anthropic-test-personal' -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' -d '{"model":"claude-haiku-4-5","max_tokens":50,"messages":[{"role":"user","content":"hi"}]}'` → real Anthropic response, no error.
2. Kill proxy process → launchd relaunches <2s (`launchctl list | grep shh`).
3. Invalid dummy token → 404 JSON with hint to run `shh connect`.
4. Streaming request forwards every SSE chunk byte-for-byte; no buffering-introduced lag >100ms.
5. Three concurrent requests to same key: all succeed (no mutex contention).
6. Same request against OpenAI + Gemini endpoints; verify correct auth header shape per provider.

**Risk:** SwiftNIO + AsyncHTTPClient streaming is new territory. If stuck, fallback: SwiftNIO in main app with post-hoc XPC refactor (less secure but unblocks).

---

### Phase 4 — Cost tracker + SQLite
**Files:**
- `Shh/Store/DatabaseManager.swift` — GRDB setup at `~/Library/Application Support/shh/log.sqlite`; migrations versioned from v1
- `Shh/Store/Schema+v1.swift` — `requests` table: `id, ts, provider, model, input_tokens, cached_input_tokens, cache_write_tokens, output_tokens, cost_usd, duration_ms, status, project_tag, key_id, request_id`
- `Shh/Pricing/prices.v1.json` — bundled, from research §5
- `Shh/Pricing/PriceTable.swift` — load bundled + fetch-and-verify signed manifest from `github.com/avirum-llc/shh-prices`
- `Shh/Pricing/TokenCounter.swift` — provider dispatch:
  - OpenAI: [TiktokenSwift](https://github.com/narner/TiktokenSwift) via SPM
  - Anthropic: `len(text)/3` heuristic for UI preview; post-hoc truth from response `usage`
  - Gemini: byte-length heuristic for preview; truth from `usageMetadata`
- `Shh/Pricing/UsageExtractor.swift` — parse stream chunks per provider for final `usage` block
- `ShhProxy/Forwarder.swift` (extend) — invoke `UsageExtractor` on stream end, write `RequestLog` row via XPC
- `Shh/Views/DashboardWindow.swift` — 640px, per §4 design: time toggle, hero number (44px light tnum), 19-bar sparkline, per-project breakdown

**Verification:**
1. Make 5 requests through proxy (mix of Anthropic + OpenAI + Gemini); 5 rows in SQLite with correct 4D tokens.
2. Compare computed cost to the response's billed cost (from dashboard): within 5%.
3. Dashboard hero matches today's SUM in SQLite.
4. Sparkline shows hourly bars for last 24h.
5. Per-project breakdown respects project tag (derived from dummy-token slug, not CWD).
6. Relaunch app → dashboard numbers persist.

**Risk:** Opus 4.7 tokenizer change (~35% higher) means users may see surprise cost jumps. Bundle a note in release notes.

---

### Phase 5 — CLI connect flows
**Files:**
- `Shh/Connect/DetectInstalledCLIs.swift` — `which claude`, `which codex`, `which aider`, `which opencode`, `which gemini`
- `Shh/Connect/ClaudeCode.swift` — writes `~/.claude/settings.json` with env vars:
  - `ANTHROPIC_BASE_URL=http://127.0.0.1:18888`
  - `ANTHROPIC_AUTH_TOKEN=shh-anthropic-<project>-<key>`
  - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
  - `DISABLE_TELEMETRY=1`
  - `DISABLE_ERROR_REPORTING=1`
  - (diff preview in sheet; warn about 1M-context tradeoff)
- `Shh/Connect/Codex.swift` — `~/.codex/config.toml` patch OR env var append to shell config (user picks)
- `Shh/Connect/Aider.swift` — `~/.aider.conf.yml` patch (openai-api-base, anthropic-api-base)
- `Shh/Connect/OpenCode.swift` — write/merge `~/.config/opencode/opencode.json`:
  ```json
  { "provider": { "anthropic": { "baseURL": "http://127.0.0.1:18888", "apiKey": "{env:SHH_ANTHROPIC_TOKEN}" } } }
  ```
  + sets `SHH_ANTHROPIC_TOKEN` in shell rc
- `Shh/Connect/GeminiCLI.swift` — env-var append (`GOOGLE_GEMINI_BASE_URL`, `GEMINI_API_KEY`)
- `Shh/Views/ConnectSheet.swift` — detect-first UI per §4 design (tool list, state pills, one primary action per row)
- `Shh/Views/DiffPreview.swift` — shows old/new config diff before write

**Verification (real CLIs in real project dirs):**
1. Install Claude Code (`npm i -g @anthropic-ai/claude-code`). Create a test project dir. Run `shh connect claude-code`. Cd to the project. Run `claude "hi"` → response comes back. Check SQLite: request logged with project tag = test-project.
2. Repeat for Codex, Aider, OpenCode, Gemini CLI. Each should log a request with the correct provider + project.
3. Disconnect flow (from Connect sheet) → restores original config (verify via diff). Subsequent CLI call fails cleanly ("proxy not configured").

**Risk:** CLI version drift — Claude Code, Codex, etc. ship weekly. Track versions used in tests; surface in release notes.

---

### Phase 6 — `shh` CLI
**Files:**
- `shh-cli/Sources/shh/ShhCommand.swift` — root swift-argument-parser
- `shh-cli/Sources/shh/Run.swift` — `shh run -- <cmd...>` spawns child with env vars pointing at proxy + injects `shh-*` dummy token based on detected CWD project
- `shh-cli/Sources/shh/Status.swift` — `shh status` → proxy reachable? vault unlocked? # keys, # projects; exit 0/1 for scripting
- `shh-cli/Sources/shh/Spend.swift` — `shh spend [--today|--week|--month|--since <date>]`; query SQLite over XPC
- `shh-cli/Sources/shh/Keys.swift` — `shh keys` list (last-4 only); `shh keys add --provider anthropic --label personal` flow
- `shh-cli/Sources/shh/Quiet.swift` — `shh quiet [--until <time>|--for <duration>]` pauses logging; restores on timeout
- Build phase: copy built binary to `Shh.app/Contents/MacOS/shh-cli`
- `Shh/Services/CLISymlinkInstaller.swift` — first-run offers to symlink `Shh.app/Contents/MacOS/shh-cli` → `/usr/local/bin/shh` (user sheet with explanation)

**Verification:**
1. `shh status` returns formatted output; exits 0 when proxy is running.
2. `shh run -- claude "hi"` → response; SQLite row tagged to CWD project.
3. `shh spend --today` → matches dashboard to the cent.
4. `shh keys` → last-4 only, never shows full key.
5. `shh quiet --for 10m` → requests during that window aren't logged; auto-resumes.

---

### Phase 7 — Onboarding + polish
**Files:**
- `Shh/Views/FirstRun/ThreatModelScreens.swift` — 3 screens per §9 UX principle: where keys live / why the proxy / what happens if you don't use it
- `Shh/Views/FirstRun/ScannerPrompt.swift` — after threat model, offer scan immediately
- `Shh/Views/Empty/NoKeys.swift`, `ProxyDown.swift`, `NotConnected.swift`
- `Shh/Views/SettingsSheet.swift` — brutally short: reset vault, export encrypted backup, refresh price table, disconnect all CLIs, quit
- `Shh/Models/Export.swift` — FR-V7 encrypted-with-passphrase export (age or ChaCha20-Poly1305 via CryptoKit)

**Verification:** Clean install (trash `~/Library/Application Support/shh/`, remove Keychain items, clear LaunchAgent) → first launch → 3 screens → scanner finds seeded keys → migrate → MenuBarExtra populated → all without manual Xcode intervention.

---

### Phase 8 — Release pipeline + README
**Files:**
- `.github/workflows/release.yml`:
  1. On tag `v*.*.*`: `xcodebuild archive` → `xcodebuild -exportArchive`
  2. `codesign --deep --force --options=runtime` with Developer ID from secret
  3. `create-dmg` for the bundle
  4. `xcrun notarytool submit <dmg> --apple-id <secret> --team-id <secret> --password <secret> --wait`
  5. `xcrun stapler staple <dmg>`
  6. Create GitHub Release with DMG asset
  7. `generate_appcast` → commit updated `appcast.xml` to repo root
  8. Trigger downstream PR to `avirum-llc/homebrew-shh` updating cask version + SHA256
- `README.md` — demo GIF (record with Cleanshot), comparison table (from PRD §13), threat-model section, install instructions (Homebrew one-liner + DMG + build-from-source), contributor guide, THREAT_MODEL.md link
- `THREAT_MODEL.md` — standalone version of §8 from PRD
- `BUILD_LOG.md` — starts today; Claude appends dated entries each session
- `homebrew-shh/Casks/shh.rb` — initial formula pointing at v0.1.0 DMG URL + SHA256

**Verification:**
1. Tag `v0.1.0-test` → CI green → DMG downloadable from GitHub Releases.
2. Fresh Mac (or Migration Assistant-cleared account) → `brew tap avirum-llc/shh && brew install --cask shh` → app installs, Gatekeeper OK, app opens, first-run flow fires.
3. Tag `v0.1.1-test` → Sparkle in v0.1.0 sees update within 24h → installs silently.
4. README demo GIF plays inline on github.com.

---

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Claude Code changes telemetry flags or env vars | Med | Keep env-var list in `Resources/cli-integration.json`; adapter per CLI; version-pin tested CLI versions in release notes |
| SwiftNIO + XPC architecture more complex than planned | Med | Phase 3 has fallback to in-process SwiftNIO; clean XPC boundary migration possible later |
| Anthropic ships built-in secrets mgmt (#29910) | Low (no staff comment as of Apr 2026) | Multi-provider + cost-tracker wedge survives; update positioning if they ship |
| Keycard adds proxy + tracker before shh ships | Low (they've been vault-only) | Faster shipping; distinctive three-in-one pitch |
| Scanner FPs on undocumented Tier 2 formats | Med | Two-signal classifier (regex + env-name); user always confirms migration |
| macOS Tahoe Keychain regressions | Med | Test on Tahoe + Sequoia + Sonoma early; Swift APIs unaffected by the CLI regression per research |
| Personal-key users can't reconcile via billing APIs | Known | Permanent "estimated" UI label; add `shh config admin-key` in v0.5 for org users |
| Opus 4.7 tokenizer change → wrong pre-request estimates | Known | Bundle changelog note; pre-request heuristic is only for UI preview, not cap enforcement (caps are deferred anyway) |

---

## One-way doors (finalize before Phase 0 / early phases)

| Decision | When | Default |
|---|---|---|
| Bundle ID `com.avirumapps.shh` | Phase 0 | Per PRD |
| XPC service ID `com.avirumapps.shh-proxy` | Phase 0 | " |
| LaunchAgent label | Phase 0 | " |
| `/usr/local/bin/shh` CLI name | Phase 6 | Per PRD |
| Dummy token format `shh-<provider>-<project>-<key>` | Phase 3 | Proposed |
| GRDB schema v1 | Phase 4 | Via migrations |
| License | Phase 0 | **MIT per PRD — confirm with Manish** |
| Homebrew tap `avirum-llc/homebrew-shh` | Phase 8 | Per PRD |
| Apple Developer team ID | Phase 0 | **Presumed same as Roast — confirm with Manish** |

## Estimated shape

8 phases. v0.1 dogfood-ready after Phase 5 (Manish + 3 friends). Public-ready after Phase 8.

---

## What I need from Manish before Phase 0

1. **License** — MIT (default per PRD) or AGPL (cmux's choice, prevents closed-source forks)?
2. **Apple Developer team ID** — same as Roast? (Can pull from existing Xcode project if yes.)
3. **GitHub org name** — `avirumapps` per PRD — confirm before I create the repo.
4. **Name collision check** — is `shh` still the name, or has anything shifted? Also confirm `shh.avirumapps.com` is the intended homepage.

---

Exit: **Ready to implement. Continue?**
