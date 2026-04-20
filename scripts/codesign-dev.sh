#!/usr/bin/env bash
# Sign the dev `shh` binary with an Apple Development cert + Keychain
# entitlement. Run this after `swift build` to enable real Keychain tests
# from the command line. The release pipeline (Phase 8) will use Developer
# ID Application instead, driven from Xcode and GitHub Actions.
set -euo pipefail

BINARY="${1:-.build/debug/shh}"
ENTITLEMENTS="shh-cli.entitlements"

if [ ! -f "$BINARY" ]; then
    echo "Binary not found at $BINARY — run 'swift build' first." >&2
    exit 1
fi

if [ ! -f "$ENTITLEMENTS" ]; then
    echo "Entitlements file not found at $ENTITLEMENTS." >&2
    exit 1
fi

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
if [ -z "${IDENTITY:-}" ]; then
    echo "No 'Apple Development' signing identity found. Install one via Xcode -> Settings -> Accounts." >&2
    exit 1
fi

TEAM_ID=$(echo "$IDENTITY" | sed -n 's/.*(\([^)]*\)).*/\1/p')
if [ -z "${TEAM_ID:-}" ]; then
    echo "Could not parse team ID from identity '$IDENTITY'." >&2
    exit 1
fi

TMP_ENTITLEMENTS=$(mktemp -t shh-entitlements)
trap 'rm -f "$TMP_ENTITLEMENTS"' EXIT
sed "s|\$(AppIdentifierPrefix)|${TEAM_ID}.|g" "$ENTITLEMENTS" > "$TMP_ENTITLEMENTS"

echo "Signing $BINARY with '$IDENTITY'..."
codesign --force --sign "$IDENTITY" --entitlements "$TMP_ENTITLEMENTS" "$BINARY"
echo "Signed. Keychain access-group: ${TEAM_ID}.com.avirumapps.shh"
