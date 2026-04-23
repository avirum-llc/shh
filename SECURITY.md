# Security policy

## Reporting a vulnerability

Please report security issues privately via
[GitHub Security Advisories](https://github.com/avirum-llc/shh/security/advisories/new)
on the `avirum-llc/shh` repository, or by email to `security@avirumapps.com`.

Do not file a public GitHub issue for security-sensitive bugs.

We'll acknowledge receipt within 72 hours and aim to have a remediation
plan within 7 days.

## Scope

`shh` stores API keys in macOS Keychain and forwards them to provider APIs
via a local proxy. Security-relevant surfaces include:

- The Keychain read path (`ShhCore.Vault`)
- The local HTTP proxy (request forwarding, header rewriting)
- The XPC channel between the menubar app and the proxy service
- The scanner's file-read behavior
- The CLI integrations that modify shell and CLI config files

See [`THREAT_MODEL.md`](THREAT_MODEL.md) for the detailed model.

## Out of scope

- Malicious code running as the same user that specifically targets shh
  (e.g. privilege-escalated Keychain read). The user has bigger problems.
- Compromise of the upstream provider's API itself.
- User error (pasting a real key into a chat with a model, checking a
  real key into a public repo). We harden defaults; we can't prevent
  deliberate disclosure.
