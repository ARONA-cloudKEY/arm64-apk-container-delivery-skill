#!/usr/bin/env bash
# Copy into a project root and adapt names/package. No Gradle, no emulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/lib/android-sdk}}"
ANDROID_JAR="$SDK_ROOT/platforms/android-34/android.jar"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
GEN="$BUILD/generated"
CLASSES="$BUILD/classes"
KEYSTORE="$ROOT/keystore/debug.p12"
ALIAS="debug"
PASS="android"
APK="$DIST/App.apk"

if [ -d /usr/lib/jvm/java-17-openjdk-arm64 ]; then
  JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-arm64}"
fi
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/}javac"
KEYTOOL="${JAVA_HOME:+$JAVA_HOME/bin/}keytool"
AAPT2="${AAPT2:-$SDK_ROOT/build-tools/debian/aapt2}"
DX="${DX:-$SDK_ROOT/build-tools/debian/dx}"
ZIPALIGN="${ZIPALIGN:-$(command -v zipalign || true)}"
APKSIGNER="${APKSIGNER:-$(command -v apksigner || true)}"

for t in "$ANDROID_JAR" "$AAPT2" "$DX" "$ZIPALIGN" "$APKSIGNER" "$JAVA" "$JAVAC"; do
  [ -e "$t" ] || { echo "missing: $t" >&2; exit 1; }
done

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$GEN" "$CLASSES" "$DIST" "$ROOT/keystore"

# 1. Resources.
"$AAPT2" compile --dir "$ROOT/res" -o "$BUILD/resources.zip"
"$AAPT2" link -o "$BUILD/base.apk" -I "$ANDROID_JAR" \
  --manifest "$ROOT/AndroidManifest.xml" --java "$GEN" \
  --min-sdk-version 26 --target-sdk-version 34 "$BUILD/resources.zip"

# 2. Java 8 bytecode against android.jar.
mapfile -t SOURCES < <(find "$ROOT/src" -name '*.java' -print | sort)
mapfile -t R_SOURCES < <(find "$GEN" -name '*.java' -print | sort)
"$JAVAC" -encoding UTF-8 -source 8 -target 8 -Xlint:-options \
  -bootclasspath "$ANDROID_JAR" -d "$CLASSES" "${SOURCES[@]}" "${R_SOURCES[@]}"

# 3. Dex + package.
"$DX" --dex --min-sdk-version=26 --output="$BUILD/classes.dex" "$CLASSES"
cp "$BUILD/base.apk" "$BUILD/unaligned.apk"
( cd "$BUILD" && zip -q -9 unaligned.apk classes.dex )
"$ZIPALIGN" -f 4 "$BUILD/unaligned.apk" "$BUILD/aligned.apk"

# 4. Debug signing (replace for any real release).
if [ ! -f "$KEYSTORE" ]; then
  "$KEYTOOL" -genkeypair -keystore "$KEYSTORE" -storetype PKCS12 \
    -storepass "$PASS" -keypass "$PASS" -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -sigalg SHA256withRSA -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US" -noprompt >/dev/null 2>&1
fi
"$APKSIGNER" sign --ks "$KEYSTORE" --ks-key-alias "$ALIAS" \
  --ks-pass "pass:$PASS" --key-pass "pass:$PASS" \
  --v1-signing-enabled false --v2-signing-enabled true \
  --v3-signing-enabled true --v4-signing-enabled false \
  --out "$APK" "$BUILD/aligned.apk"

# 5. Verification and deliverables.
"$APKSIGNER" verify --verbose --print-certs "$APK" | tee "$DIST/verify.txt"
"$ZIPALIGN" -c -v 4 "$APK" > "$DIST/zipalign.txt"
tail -1 "$DIST/zipalign.txt"
"$AAPT2" dump badging "$APK" | tee "$DIST/badging.txt"
unzip -Z1 "$APK" > "$DIST/contents.txt"
sha256sum "$APK" > "$DIST/SHA256SUMS.txt"

# Optional source archive.
if [ -f "$ROOT/README.md" ]; then
  ( cd "$ROOT" && zip -qr "$DIST/app-source.zip" \
      AndroidManifest.xml res src test build.sh README.md 2>/dev/null || true )
fi
chmod 0644 "$APK" "$DIST"/* 2>/dev/null || true
echo "BUILD SUCCESSFUL: $APK"
