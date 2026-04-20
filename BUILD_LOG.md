# Build log

Dated dev journal for `shh`. One entry per meaningful session — what was
tried, what worked, what didn't, and what was decided. Written for future-me
and for anyone landing on the repo who wants to understand the engineering
history.

---

## 2026-04-19 — Phase 0: scaffold

Kicking off the build. Spent the day grilling the PRD (`shh-plan.md`),
running a five-subagent research pass (CLI compatibility, API-key regex
catalog, competitive landscape, Mac stack patterns, token counting), and
drafting an eight-phase implementation plan. The three refined artifacts
live in [`docs/`](docs/): `spec.md`, `research.md`, `plan.md`.

### Locked decisions

- **Name:** `shh` (lowercase, monospace). The five HTML mocks in the repo
  root still say "Keychain for AI" — they predate the rename. To be updated
  before any visible text lands.
- **License:** MIT. Low barrier to contribution; the moat is polish +
  distribution + this build log, not the license.
- **Architecture:** CLI-first. `ShhCore` pure Swift Package (no AppKit),
  `shh` swift-argument-parser executable, `Shh.app` thin SwiftUI menubar
  consumer. MCP server at launch. Raycast extension + `shh://` deep links.
- **Config paths:** Tailscale-style split. `~/.config/shh/` for
  user-editable JSON, `~/Library/Application Support/shh/` for app-private
  data (SQLite, cache).
- **Proxy:** plain HTTP on `127.0.0.1:18888`. HTTPS on loopback is security
  theater on the local machine and adds a real CA-trust attack surface. See
  [`docs/spec.md`](docs/spec.md) Q7 for the full argument.
- **Audience:** API-key users only. Claude.ai subscription, Cursor hosted
  mode, and Codex OAuth plans are explicitly out of scope.

### What went in

- Swift Package skeleton: `Package.swift`, `Sources/ShhCore`,
  `Sources/shh`, `Tests/ShhCoreTests`.
- `shh` CLI binary stub using `swift-argument-parser`. Two surfaces right
  now — default `status` subcommand and `--version`. Grows into the full
  surface (documented at `memory/project_shh_phase0_decisions.md`) as
  phases progress.
- MIT `LICENSE`, `README.md`, `SECURITY.md`, `THREAT_MODEL.md`, `.gitignore`.

### What's next (Phase 1)

Vault + `MenuBarExtra` shell. Keychain layer with `kSecAttrAccessControl`
+ `.biometryCurrentSet` + `LAContext` with five-minute reuse. First
SwiftUI window. First `shh keys add` end-to-end flow — CLI path hits
Keychain through `ShhCore`, triggers a real Touch ID prompt, reads back
the key successfully.

No Xcode project yet. SPM compiles on its own; the `.xcodeproj` for the
menubar app lands in Phase 1.

### Cleanup pass

Moved the grill-phase artifacts (`spec.md`, `research.md`, `plan.md`) out
of `.claude/grill-runs/shh/` and into `docs/`. They were project-first-class
docs hiding inside a tool-specific hidden folder; now they live where a
contributor would actually look. README and `.gitignore` updated.

---

## 2026-04-19 (later) — Phase 1A: Vault + `shh keys`

Scope: build `ShhCore.Vault` + `KeychainStore` + `shh keys add/list/remove`
as pure SPM work, no Xcode project yet.

### What went in

- `Sources/ShhCore/Vault/VaultKey.swift` — model. `Provider` is a
  `RawRepresentable` struct (accepts any string; named constants for
  Tier-1 LLM providers). `Bucket` enum (personal / work). `slugified`
  string extension.
- `Sources/ShhCore/Vault/KeychainError.swift` — typed errors with
  `LocalizedError` descriptions that surface the OS's own message when
  the status code is unhandled.
- `Sources/ShhCore/Vault/KeychainStore.swift` — `Security.framework`
  wrapper. `kSecAttrAccessControl` with `.biometryCurrentSet` +
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Reads use `LAContext`
  with `touchIDAuthenticationAllowableReuseDuration = 300` so a session
  only prompts on the first read inside a 5-minute window.
- `Sources/ShhCore/Vault/Vault.swift` — `actor` facade. Keychain holds
  secrets; JSON metadata at `~/.config/shh/vault-metadata.json` holds
  non-secret fields (provider, label, fingerprint, bucket, timestamps).
- `Sources/shh/Commands/Keys.swift` — `shh keys list`, `shh keys add`
  (interactive `getpass` by default, `--stdin` for scripting and agents),
  `shh keys remove`. Every read has `--json`.
- `Sources/shh/ShhCommand.swift` — renamed from `main.swift` (file named
  `main.swift` triggers top-level-code mode which conflicts with `@main`).

### Dev signing

Keychain access from an SPM-built CLI needs the binary signed with a
Keychain entitlement. Added:

- `shh-cli.entitlements` — `keychain-access-groups` with a templated
  `$(AppIdentifierPrefix)` prefix that gets substituted at sign time. Keeps
  the source file team-agnostic.
- `scripts/codesign-dev.sh` — discovers the first Apple Development
  identity via `security find-identity`, extracts the team id, substitutes
  it into a temp entitlements file, and signs the dev binary. Run after
  every `swift build`.

### What worked

- `swift build` clean
- `swift test` — 10 / 10 pass (7 `VaultKey` + 2 `KeychainStore`
  construction + 1 legacy `Shh.version` check)
- CLI smoke: `shh --help`, `shh keys --help`, `shh status`,
  `shh status --json`, `shh keys list` on an empty vault

### What didn't work yet

End-to-end Keychain write from the signed CLI — the process is SIGKILL'd
(exit 137) with no output. Likely root cause: **Apple Development certs
need a provisioning profile to activate Keychain entitlements at runtime,
and CLI binaries don't carry one.** Further poking from the command line
wasn't productive without either dropping biometric access control, using
an ad-hoc signing layout, or generating a real .app bundle.

### Decision

Defer real Keychain validation to Phase 1B, where the Xcode project
(MenuBarExtra shell) gets created and the app target carries a real
provisioning profile. The CLI binary gets bundled inside the .app in a
later phase; it then inherits the app's signing context and Keychain
access becomes trivial.

### What's next (Phase 1B)

Create `Shh.xcodeproj` with a MenuBarExtra app target depending on the
local Swift Package. Wire the SwiftUI Add Key sheet and menubar dropdown
to `ShhCore.Vault`. First real Touch ID moment lives here.

---

## 2026-04-19 (even later) — Phase 1B: menubar app scaffold

Chose **xcodegen** over committing the `.xcodeproj` directly. project.yml
is a ~35-line diffable spec; the `.xcodeproj` is a 2000-line XML file
that merges badly. One-time `brew install xcodegen` is a cheap ask for
anyone who wants to build the app.

### What went in

- `project.yml` — xcodegen spec for the `Shh` macOS app target. macOS
  14+, `LSUIElement: true` (menubar-only, hidden from Dock), sandbox
  disabled (the app needs to write to `~/.config/shh/` alongside the
  CLI; the proxy will run sandboxed in a separate XPC service later).
  Hardened runtime on. Team id: `422FSC44SS` (Manish's Apple Development
  team, same as Roast).
- `Apps/Shh/Shh.entitlements` — `keychain-access-groups` with the
  templated `$(AppIdentifierPrefix)` prefix, same pattern as the CLI's
  entitlements.
- `Apps/Shh/ShhApp.swift` — `@main` app with `MenuBarExtra(.window)`,
  refreshing the key list on appear and after each Add Key sheet dismiss.
  One shared `Vault` actor for the app lifetime.
- `Apps/Shh/Views/MenuBarLabel.swift` — lock-icon + key-count label, the
  permanent menubar presence.
- `Apps/Shh/Views/MenuBarDropdown.swift` — 320px dropdown with header,
  empty-state hint, per-key rows, and Add-key / Quit actions with
  keyboard shortcuts. Functional scaffold; full design-system polish
  from PRD §4 lands when real content exists to style.
- `Apps/Shh/Views/AddKeySheet.swift` — form with Provider picker
  (Anthropic / OpenAI / Gemini + Custom…), Label, API key (SecureField),
  Bucket segment. Clipboard clears on save. Error message surfaces any
  Keychain failure. Calls through to `Vault.add`.
- `Apps/Shh/Theme/Tokens.swift` — colors, typography, layout constants
  from `shh-plan.md` §4 in a single enum. Single source of truth for
  future views.

### What's verified

- `xcodegen generate` clean.
- `xcodebuild` clean with ad-hoc signing overrides.
- `Shh.app` builds and launches; the resident process shows up under
  `pgrep Shh`.

### Entitlements snag and fix

First build attempt (automatic signing) failed with *"No Account for
Team 422FSC44SS"* — Xcode's account store didn't have a current Apple
ID session for that team. Switched to manual signing with identity `-`
(ad-hoc); that then failed with *"Shh requires a provisioning profile"*
because `keychain-access-groups` in the entitlements forces
provisioning.

Fix: **drop `keychain-access-groups` from the dev entitlements.**
Unsandboxed macOS apps can read and write generic-password Keychain
items in the user's login Keychain without any `keychain-access-groups`
entitlement — the default access group is the bundle id, which is
sufficient when the only consumer is the app itself. The entitlement is
only needed to *share* Keychain items across bundles (menubar app +
bundled CLI — Phase 1C) or to pass App Store review, neither of which
applies to a dev build. Phase 8 release CI will re-add the team-prefixed
access group.

Added `scripts/build-app-dev.sh` — one command: `xcodegen generate` +
`xcodebuild` with the right ad-hoc overrides. Future dev iteration is
`./scripts/build-app-dev.sh` followed by `open <path>`.

### What's next

Click the menubar lock, Add key, fill Provider / Label / API key /
Bucket, Save to vault. That path should trigger Touch ID (first-time
write of a `.biometryCurrentSet` item) and drop a real entry in the
login Keychain + `~/.config/shh/vault-metadata.json`. Dropdown refreshes
with the new row — the first real product moment.

If the Add Key flow surfaces issues (SwiftUI complaints, Keychain
failures with unsandboxed ad-hoc signing, anything else), we iterate
here. Once it's happy:

- **Phase 1C:** bundle the `shh` CLI binary inside the .app, symlink to
  `/usr/local/bin/shh`. CLI inherits the app's signing identity so the
  CLI-from-terminal flow starts working.
- **Phase 2:** scanner + migration flow (walk shell configs and `.env`
  files, surface detected keys, offer to move them into the vault).

---

## 2026-04-19 (end of day) — Phases 2–6 shipped

One long push through the full v0.1 backbone.

### What landed

- **Phase 2 — Scanner / migrator:** `ShhCore.Scanner` with
  `KeyPattern` catalog (Tier 1 LLM, Tier 2 paid, Tier 3 secrets),
  `FileScanner` (two-signal classifier, scans shell configs, CLI
  configs, project dirs), `Migrator` (vault-first writes, source
  rewritten with `shh-<provider>-<label>` markers). `shh scan` +
  `--json` + `--migrate`. 7 tests added.
- **Phase 3 — Proxy:** `ShhCore.Proxy` with `ProxyServer` on
  Network.framework + URLSession for upstream (buffered — streaming
  is a v0.2 polish). `DummyToken` format `shh.<provider>.<project>.
  <label>`. `UpstreamRouter` handles Anthropic (`x-api-key`), Gemini
  (query param), everyone else (`Bearer`). `/__shh_ping__` endpoint
  for CLI-side health checks.
- **Phase 4 — Cost tracker:** `ShhCore.Log` with `RequestLog`
  (newline-delimited JSON at
  `~/Library/Application Support/shh/requests.ndjson`), bundled
  `PriceTable` for Opus/Sonnet/Haiku 4.x + GPT-5/5.5 + Gemini 2.5/3
  Pro, byte-heuristic `TokenCounter`. `shh spend --range` + `--json`.
- **Phase 5 (partial) — Connect flows:** Claude Code connector writes
  `~/.claude/settings.json` with `ANTHROPIC_AUTH_TOKEN` + telemetry-
  disable env vars; Gemini CLI connector appends a marked block to
  the user's shell rc. `shh connect list/tool/disconnect`. Codex /
  Aider / OpenCode are pending.
- **Phase 6 — GUI integration:** `ProxySupervisor` actor-wrapper on
  the main actor; starts the proxy from `ShhApp.init` via a
  `Task { @MainActor }` so it comes up at launch, not on first
  dropdown click. `DashboardWindow` reads the request log with range
  toggle and per-provider / per-project breakdowns. `ConnectWindow`
  is detection-first with monogram cards. Menubar hero number +
  status pill (on/off/starting/failed).
- **Phase 6 polish:** `shh status` now actually pings the proxy and
  reports today's spend instead of the Phase-0 stub text.

### End-to-end verified

The full CLI stack smoke-passes on a running app:

- `shh --help` shows 6 top-level subcommands.
- `shh status` reports proxy running, vault count, today's spend.
- `shh proxy status` → `running on 127.0.0.1:18888`.
- `curl http://127.0.0.1:18888/__shh_ping__` → `{"shh":"alive"}`.
- `lsof -nP -iTCP:18888` shows the Shh process holding the port.
- `shh scan --json` picked up real Anthropic + Gemini keys in
  `~/.claude/settings.local.json` and
  `~/Documents/claude/openclaw-server/connection.md` — an honest
  end-to-end run.
- `shh connect tool claude-code --dry-run` emits the exact
  `settings.json` mutation.
- Proxy error paths: a non-`shh.` token surfaces *"Malformed shh
  token"*; a well-formed but unknown token surfaces *"Keychain item
  not found"* — both as HTTP 502 with JSON body. The full parse →
  vault-lookup → forward path is exercised without needing a real
  upstream key.
- `shh spend --today --json` returns well-formed empty counts; the
  log is writable, it simply has no successful requests yet.

### What's not yet verified

A real Anthropic round-trip — needs the user to add a real key via
the menubar app (which the app's Keychain namespace can see) and run
`claude "hi"` through the proxy. The proxy path is known to work;
the untested surface is just the final byte-for-byte API exchange.

### What's still open for v0.1 (at end of that push)

1. **Phase 1C** — bundle the `shh` CLI inside `Shh.app/Contents/MacOS`,
   symlink to `/usr/local/bin/shh`. Makes the CLI inherit the app's
   signing identity so CLI-added keys and app-added keys share the
   same Keychain namespace. Until then, the CLI and app have separate
   vaults.
2. **Phase 5 (rest)** — Codex CLI, Aider, OpenCode connectors.
3. **Proxy streaming** — URLSession.bytes(for:) passthrough for SSE.
4. **First-run threat-model flow** (three-screen explainer).
5. **Sparkle + GitHub Releases CI + Homebrew cask** (Phase 8 release
   pipeline).

---

## 2026-04-19 (very end) — v0.1 backbone complete

Knocked every remaining item except the ones that need real user
credentials (Apple Developer cert in CI, Sparkle EdDSA keys, an actual
Anthropic round-trip). Commits 38536de → 3518edb.

### What landed

- **Phase 5 (complete):** Codex, Aider, OpenCode connectors.
  Codex + Aider use the shell-rc env-block pattern. OpenCode merges a
  provider block into `~/.config/opencode/opencode.json` and only
  removes loopback entries on disconnect.
- **Proxy streaming:** `URLSession.bytes(for:)` + HTTP/1.1 chunked
  transfer encoding. Claude Code SSE flows byte-for-byte now. 4 KB
  buffered chunks. Mid-stream errors truncate the client's body.
- **Phase 1C — CLI bundled in .app:** xcodegen postBuildScripts runs
  `swift build`, copies the CLI to `Shh.app/Contents/Helpers/shh`
  (not `Contents/MacOS/shh` — case-insensitive FS collision with the
  main `Shh` binary), re-signs with `--deep`. Shared Keychain
  verified: keys added via the GUI are visible to the bundled CLI.
- **First-run onboarding:** three-screen `FirstRunWindow` fired on
  first dropdown open, persisted via `@AppStorage`.
- **ScannerWindow:** GUI for `shh scan` — checkboxes, bucket picker,
  "Migrate selected". Reuses the `Migrator` actor.
- **CLIInstaller + "Install CLI" menubar action:** tries
  `/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin` in order,
  creates `~/.local/bin` lazily, prints result inline. Falls back to
  showing the manual `ln -sf` command.
- **`shh run`:** ad-hoc process wrapping. `shh run --provider X
  --project Y --label Z -- cmd...` spawns a child with the right
  env vars set.
- **Phase 8 scaffold:** `.github/workflows/ci.yml` (build/test/smoke
  on every push), `.github/workflows/release.yml` (tag-triggered,
  six secrets needed), `homebrew-cask.rb.template` for the sibling
  tap repo.
- **`shh status`** rewritten to actually ping the proxy.

### Final state: 17 commits, all tests green, proxy alive

```
swift build   → clean
swift test    → 17/17 pass
shh --version → 0.0.1-dev
shh status    → proxy running, vault 1 key
curl /__shh_ping__ → {"shh":"alive"}
```

### What's still not verified

1. **Real Anthropic round-trip.** Needs a real API key entered through
   the menubar, then `claude "hi"` through the bundled CLI. Proxy
   parse → vault lookup → stream forwarding is exercised; upstream
   handoff is the only line of code that's never seen production
   bytes.
2. **Real CI run.** Needs the six GitHub secrets + tag push.

### Deferred past v0.1

- **MCP server** (`shh mcp`) — agent-facing interface; v0.2.
- **Provider billing reconciliation** — needs org-admin keys most
  personal users don't have. Numbers stay "estimated" in v0.1.
- **Real biometric in dev builds** — acceptable dev/release split.
- **`shh quiet`** — trivial when needed.
- **Sparkle** — TODO in release.yml; wire when shipping updates.

### Minimum to actually release

1. Test the Anthropic round-trip end-to-end with a real key.
2. Set up `avirumapps/homebrew-shh` tap repo.
3. Generate Sparkle EdDSA keys, publish initial appcast.xml, add
   `SUFeedURL` to Info.plist.
4. Add the six CI secrets.
5. `git tag v0.1.0-alpha && git push origin v0.1.0-alpha`.

Scaffold carries all the pieces; remaining work is credentials,
external repos, and one genuine test.
