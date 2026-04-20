# shh

*Your AI keys never speak above a whisper.*

`shh` is a local macOS menubar app that stores LLM API keys in Apple Keychain,
injects them into AI coding tools (Claude Code, Codex, Aider, OpenCode,
Gemini CLI) through a local proxy so the agent never sees the real key, and
tracks combined spend across providers in real time.

Open source. Local-first. Biometric-gated.

## Status

**Pre-alpha.** Being built in the open. Not installable yet.

See [`BUILD_LOG.md`](BUILD_LOG.md) for the dated development journal,
[`shh-plan.md`](shh-plan.md) for the original product plan, and
[`docs/`](docs/) for the refined spec, research findings, and implementation
plan that came out of the pre-build grill.

## The threat model in one paragraph

`.env` files leak API keys into Claude Code's context window, git commits,
framework caches, and shell history. `shh` replaces the real key in every
CLI's environment with a dummy token that only works against the local
proxy. The real key stays in macOS Keychain, gated by Touch ID. If an agent
runs `printenv`, it sees the dummy token — useless outside the proxy. See
[`shh-plan.md` §8](shh-plan.md) for the full threat table.

## Development

```sh
swift build
swift test
```

The `shh` CLI is the primary interface. The SwiftUI menubar app is a thin
consumer of the same `ShhCore` library — every GUI action is callable from
the CLI, and every CLI read has `--json` for scripting and agent use.

## License

MIT. See [`LICENSE`](LICENSE).
