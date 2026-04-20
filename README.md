# shh

*Your AI keys never speak above a whisper.*

`shh` is a local macOS menubar app that stores LLM API keys in Apple Keychain,
injects them into AI coding tools (Claude Code, Codex, Aider, OpenCode,
Gemini CLI) through a local proxy so the agent never sees the real key, and
tracks combined spend across providers in real time.

Open source. Local-first. Biometric-gated.

## Status

**v0.1-alpha.** All eight phases landed in the scaffold: vault, scanner,
proxy, cost tracker, CLI integrations (Claude Code / Codex / Aider /
OpenCode / Gemini CLI), menubar GUI, onboarding, release pipeline
template. Needs real-usage validation before a public release.

See [`BUILD_LOG.md`](BUILD_LOG.md) for the dated development journal,
[`shh-plan.md`](shh-plan.md) for the original product plan, and
[`docs/`](docs/) for the refined spec, research findings, and implementation
plan.

## Install

Not yet published. When it is, one of:

```sh
# Homebrew cask (after the avirumapps/homebrew-shh tap is set up)
brew tap avirumapps/shh
brew install --cask shh

# Direct DMG from GitHub Releases
open https://github.com/avirumapps/shh/releases/latest
```

Until then, build from source — see Development below.

## Quick use

```sh
# Add a key (or use the menubar Add Key button)
shh keys add --provider anthropic --label personal

# Find keys already leaked on your machine
shh scan

# Connect a CLI to the proxy
shh connect tool claude-code --project myproject --label personal

# See spend
shh spend --range today

# Run a one-off through the proxy
shh run --provider anthropic --project demo --label personal -- claude "hi"
```

## The threat model in one paragraph

`.env` files leak API keys into Claude Code's context window, git commits,
framework caches, and shell history. `shh` replaces the real key in every
CLI's environment with a dummy token that only works against the local
proxy. The real key stays in macOS Keychain, gated by Touch ID. If an agent
runs `printenv`, it sees the dummy token — useless outside the proxy. See
[`shh-plan.md` §8](shh-plan.md) for the full threat table.

## Development

### CLI and library (pure SPM)

```sh
swift build
swift test
```

Dev-signing the CLI so it can touch Keychain:

```sh
./scripts/codesign-dev.sh
```

### Menubar app (Xcode, generated from `project.yml`)

The `Shh.xcodeproj` is not committed — it's generated from `project.yml`
via [xcodegen](https://github.com/yonaskolb/XcodeGen) so contributors see
one diffable source of truth instead of a 2000-line `project.pbxproj`.

```sh
brew install xcodegen       # one-time
xcodegen generate            # any time project.yml changes
open Shh.xcodeproj
```

### Architecture

The `shh` CLI is the primary interface. The SwiftUI menubar app is a thin
consumer of the same `ShhCore` library — every GUI action is callable from
the CLI, and every CLI read has `--json` for scripting and agent use.

```
ShhCore (pure Swift, no AppKit)
├── Vault           Keychain-backed + JSON metadata
├── Scanner         regex catalog + two-signal classifier + migrator
├── Proxy           Network.framework listener + URLSession streamer
├── Log             newline-delimited JSON request log
└── Connect         per-CLI integration (claude-code, codex, aider,
                    opencode, gemini-cli)

shh CLI          Shh.app (menubar)
├── status        ├── MenuBarDropdown (key count + spend + actions)
├── keys          ├── AddKeySheet, ScannerWindow, DashboardWindow,
├── scan          │   ConnectWindow, FirstRunWindow
├── connect       ├── ProxySupervisor (starts proxy at launch)
├── run           └── CLIInstaller (symlinks bundled CLI to PATH)
├── proxy
└── spend
```

### Release (Phase 8)

`.github/workflows/release.yml` is tag-triggered. Needs these repo secrets:

- `SIGNING_CERT_P12` — base64-encoded .p12 exported from Keychain
- `SIGNING_CERT_PASSWORD`
- `APPLE_ID` — the Apple Developer account email
- `APPLE_APP_PASSWORD` — app-specific password from appleid.apple.com
- `APPLE_TEAM_ID` — 422FSC44SS
- `SPARKLE_ED_PRIVATE_KEY` — EdDSA private key for appcast signing

Homebrew cask template lives at `.github/workflows/homebrew-cask.rb.template`;
commit it into `avirumapps/homebrew-shh` to publish via `brew install --cask`.

## License

MIT. See [`LICENSE`](LICENSE).
