#!/usr/bin/env bash
# Generate Shh.xcodeproj from project.yml and build a dev .app bundle.
# Ad-hoc signed, no provisioning profile needed. The built .app can
# access the user's login Keychain because it is unsandboxed.
#
# For release builds, Phase 8 CI re-enables the team-prefixed
# `keychain-access-groups` entitlement and signs with Developer ID.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

echo "[1/3] Generating Shh.xcodeproj from project.yml..."
xcodegen generate --quiet

echo "[2/3] Building Shh.app..."
xcodebuild \
    -project Shh.xcodeproj \
    -scheme Shh \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM="" \
    build 2>&1 | tail -5

APP_PATH="$(xcodebuild -project Shh.xcodeproj -scheme Shh -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR / {print $3}')/Shh.app"

echo "[3/3] Built at: $APP_PATH"
echo
echo "Run it:"
echo "  open '$APP_PATH'"
