#!/usr/bin/env bash
# Optional: notarize a zip or .app after a Release build.
# Prerequisites: Apple Developer account, `notarytool` keychain profile, signed app.
#
# 1) Create a keychain profile (one-time):
#    xcrun notarytool store-credentials "AC_PASSWORD_NOTARY" --apple-id "you@example.com" --team-id TEAMID --password "@keychain:AC_PASSWORD"
#
# 2) Submit (example paths):
#    xcrun notarytool submit ./MenuBarMonitor.zip --keychain-profile "AC_PASSWORD_NOTARY" --wait
#
# 3) Staple:
#    xcrun stapler staple ./MenuBarMonitor.zip
#    # or: xcrun stapler staple ./MenuBarMonitor.app
#
# See README (Notarization) and Apple documentation:
# https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution

set -euo pipefail
echo "This file documents notarization steps; edit paths and run commands manually or paste them here."
exit 0
