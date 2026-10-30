#!/usr/bin/env bash
# Install a native ARM64 Android CLI build toolchain. No emulator, no VM.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (or adapt the apt/profile paths)." >&2
  exit 1
fi
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) echo "This script targets ARM64; detected $(uname -m)." >&2; exit 1 ;;
esac

SDK_ROOT="${ANDROID_SDK_ROOT:-/usr/lib/android-sdk}"
PLATFORM_ZIP="platform-34-ext7_r03.zip"
PLATFORM_URL="https://dl.google.com/android/repository/$PLATFORM_ZIP"
PLATFORM_SHA1="1f2e9478d6a7601425ceaa553311dc43191f103d"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  openjdk-17-jdk-headless android-sdk-build-tools android-sdk-common \
  dalvik-exchange curl unzip zip file ca-certificates

if [ ! -f "$SDK_ROOT/platforms/android-34/android.jar" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 3 --connect-timeout 20 -o "$tmp/$PLATFORM_ZIP" "$PLATFORM_URL"
  echo "$PLATFORM_SHA1  $tmp/$PLATFORM_ZIP" | sha1sum -c -
  unzip -q "$tmp/$PLATFORM_ZIP" -d "$tmp/unpack"
  rm -rf "$SDK_ROOT/platforms/android-34"
  mv "$tmp/unpack/android-34" "$SDK_ROOT/platforms/android-34"
fi

cat > /etc/profile.d/android-sdk.sh <<'PROFILE'
# Android CLI build environment (ARM64, no emulator).
export ANDROID_HOME="/usr/lib/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/build-tools/debian:$PATH"
PROFILE
chmod 0644 /etc/profile.d/android-sdk.sh

apt-get clean
rm -rf /var/lib/apt/lists/*

export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-arm64}"
export PATH="$JAVA_HOME/bin:$SDK_ROOT/build-tools/debian:$PATH"
export ANDROID_JAR="$SDK_ROOT/platforms/android-34/android.jar"

aapt2 dump resources "$ANDROID_JAR" >/dev/null
echo "OK"
java -version 2>&1 | head -1
aapt2 version
"$SDK_ROOT/build-tools/debian/dx" --version 2>&1 | head -1 || true
apksigner --version
