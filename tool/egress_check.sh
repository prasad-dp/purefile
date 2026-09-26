#!/usr/bin/env bash
# PureFile network-egress proof (F18 hardening gate).
#
# Verifies the OFFLINE GUARANTEE at three levels:
#   1. Source: no Dart networking primitives outside the allowlist.
#   2. Merged RELEASE manifest: no android.permission.INTERNET.
#   3. Debug builds are EXEMPT by design — Flutter's debug manifest adds
#      INTERNET for hot reload; it is stripped from every release build
#      by tools:node="remove" in the app manifest.
#
# Usage: bash tool/egress_check.sh          (checks existing artifacts)
#        bash tool/egress_check.sh --build  (rebuilds release APK first)
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
fail=0

echo "== 1. Dart source: networking primitives =="
# Allowlist: nothing. The app must not import dart:io HTTP, HttpClient,
# or any pub package that performs network I/O. (dart:io itself is fine —
# file access lives there.)
hits=$(grep -rn --include="*.dart" \
  -E "HttpClient|http\.Client|http\.get|http\.post|http\.read|\.openUrl\(|Socket\.connect|RawDatagramSocket" \
  lib/ 2>/dev/null | grep -v "_test" | wc -l)
if [ "$hits" -eq 0 ]; then
  echo "   CLEAN — no network primitives in lib/"
else
  echo "   FAIL — networking code found:"
  grep -rn --include="*.dart" \
    -E "HttpClient|http\.Client|http\.get|http\.post|http\.read|\.openUrl\(|Socket\.connect|RawDatagramSocket" \
    lib/ 2>/dev/null | head -10
  fail=1
fi

echo "== 2. Release merged manifest: INTERNET permission =="
MANIFEST="build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
  echo "   SKIP — no release build found (run: flutter build apk --release)"
  fail=1
elif grep -q "uses-permission android:name=\"android.permission.INTERNET\"" "$MANIFEST"; then
  echo "   FAIL — INTERNET present in the RELEASE manifest:"
  grep -n "INTERNET" "$MANIFEST"
  fail=1
else
  echo "   CLEAN — release build cannot access the network (OS-enforced)"
fi

echo "== 3. Debug manifest (informational) =="
DEBUG_MANIFEST="build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml"
if [ -f "$DEBUG_MANIFEST" ] && grep -q "uses-permission android:name=\"android.permission.INTERNET\"" "$DEBUG_MANIFEST"; then
  echo "   NOTE — debug manifest has INTERNET (Flutter hot-reload requirement)."
  echo "   Release builds strip it via tools:node=\"remove\" — this is expected."
else
  echo "   (no debug build present)"
fi

if [ "$fail" -eq 0 ]; then
  echo "== EGRESS CHECK PASSED =="
else
  echo "== EGRESS CHECK FAILED =="
fi
exit "$fail"
