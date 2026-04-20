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

- All source files written; exhaustive fields from project.yml provided.
- Not built yet — requires `xcodegen generate` + `open Shh.xcodeproj`
  which is a local interactive step.

### What's next

Manish runs `brew install xcodegen && xcodegen generate`, opens
`Shh.xcodeproj`, builds. On first launch: menubar lock + "0" appears,
dropdown shows empty state, Add Key sheet opens. First add should
trigger a Touch ID prompt and land a key in Keychain — the first real
product moment.

If the build reveals SwiftUI or project.yml issues, iterate. Once the
Add Key flow is happy, Phase 1C bundles the CLI binary inside the .app
and symlinks it to `/usr/local/bin/shh` so the CLI inherits the app's
signing identity. That closes the Keychain-from-CLI loop.
