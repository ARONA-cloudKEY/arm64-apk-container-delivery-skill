#!/usr/bin/env bash
# Verify signature, alignment, manifest, and core entries of an APK.
set -euo pipefail

APK="${1:?usage: verify-apk.sh path/to/app.apk}"
[ -f "$APK" ] || { echo "missing APK: $APK" >&2; exit 1; }

SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/lib/android-sdk}}"
AAPT2="${AAPT2:-$SDK_ROOT/build-tools/debian/aapt2}"
APKSIGNER="${APKSIGNER:-$(command -v apksigner || true)}"
ZIPALIGN="${ZIPALIGN:-$(command -v zipalign || true)}"
[ -x "$AAPT2" ] || { echo "missing aapt2: $AAPT2" >&2; exit 1; }
[ -x "$APKSIGNER" ] || { echo "missing apksigner" >&2; exit 1; }
[ -x "$ZIPALIGN" ] || { echo "missing zipalign" >&2; exit 1; }

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

echo "== signature =="
"$APKSIGNER" verify --verbose --print-certs "$APK" | tee "$out/verify.txt"

echo "== alignment =="
"$ZIPALIGN" -c -v 4 "$APK" > "$out/zipalign.txt"
tail -1 "$out/zipalign.txt"

echo "== manifest =="
"$AAPT2" dump badging "$APK" | tee "$out/badging.txt" \
  | grep -E "^package:|^sdkVersion|^targetSdkVersion|^application-label|^launchable-activity|^locales|^uses-permission" || true

echo "== contents =="
unzip -Z1 "$APK" > "$out/contents.txt"
for entry in AndroidManifest.xml classes.dex resources.arsc; do
  grep -qx "$entry" "$out/contents.txt" || { echo "missing $entry" >&2; exit 1; }
done
grep -E 'mipmap.*ic_launcher|drawable.*ic_launcher' "$out/contents.txt" || true

echo "== artifact =="
file "$APK"
stat -c '%s bytes' "$APK"
sha256sum "$APK"
