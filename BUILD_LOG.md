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
