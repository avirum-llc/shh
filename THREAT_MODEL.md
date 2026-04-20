# Threat model

The canonical, detailed threat model lives in [`shh-plan.md` §8](shh-plan.md).
During the initial build this file exists as a discoverable entry point and
points at the PRD. Before v0.1 release, the full threat table will be
excerpted here as a standalone document.

## One-paragraph summary

`shh` is designed so that AI coding agents cannot accidentally see, log, or
transmit real API keys during normal operation. Keys live only in the macOS
Keychain, gated by Touch ID. The CLI's environment contains only a dummy
token that identifies which key to inject — useless outside the proxy. The
real key never enters `stdout`, `.env` files, framework caches, child-process
environments, or shell history.

See [`shh-plan.md` §8](shh-plan.md) for the full table of threats, the
mechanisms that make them real today, and shh's mitigation for each.
