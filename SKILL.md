---
name: android-apk-container-delivery
description: >-
  Build, test, sign, verify, and publicly share an installable Android APK in a
  headless ARM64 Linux container without Gradle, Android Studio, an emulator, or
  a VM. Covers Ubuntu ARM64 SDK packages, API/toolchain mismatches, manual
  aapt2/dx packaging, signature and alignment checks, upload-host pitfalls, and
  download verification.
whenToUse: >-
  Use when asked to configure Android CLI builds or produce a downloadable APK
  inside a container, especially ARM64 Debian/Ubuntu where Google's Linux
  Build-Tools may be x86_64-only. Also use when a previous APK build failed with
  aapt2 resource-table errors or when a public APK link must be verified.
metadata:
  version: "1.0.0"
  lastValidated: "2026-10-27"
---

# Android APK in a headless ARM64 container

## Scope and success criteria

Deliver a real, signed, installable APK plus source and a checksum. If the user
asks to share it, deliver a public URL and prove it by downloading the file again
and comparing its hash.

Default constraint: **no emulator and no VM**. A container can build and verify
an APK without either. Do not claim runtime UI testing when no device exists.
State the limitation explicitly and cover logic with host-JVM tests plus static
APK validation.

## 1. Inventory before installing anything

```bash
uname -m; cat /etc/os-release | head -3; df -h /
command -v java javac aapt aapt2 dx apksigner zipalign curl unzip zip
command -v python3 node adb strings || true
```

Expect surprises: the validated container had Java/JDK but **no python3, no
strings, no adb**, and only ~2 GB free. Prefer shell and Node for glue. Avoid
large downloads and clean package caches when disk is tight.

## 2. Bootstrap the ARM64 toolchain

Google's Linux Build-Tools are normally x86_64. Ubuntu's ARM64 packages provide
native `aapt2`, `dx`, `zipalign`, and `apksigner`; use them instead of qemu:

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  openjdk-17-jdk-headless android-sdk-build-tools android-sdk-common \
  dalvik-exchange curl unzip zip file ca-certificates
apt-get clean; rm -rf /var/lib/apt/lists/*
```

Use **Android Platform 34**, not 35, with `aapt2 2.19-debian`:

```bash
curl -fL -o /tmp/platform-34.zip \
  https://dl.google.com/android/repository/platform-34-ext7_r03.zip
echo "1f2e9478d6a7601425ceaa553311dc43191f103d  /tmp/platform-34.zip" | sha1sum -c
unzip -q /tmp/platform-34.zip -d /tmp/platform34
mv /tmp/platform34/android-34 /usr/lib/android-sdk/platforms/android-34
```

Set a persistent environment:

```bash
export ANDROID_HOME=/usr/lib/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/build-tools/debian:$PATH"
export ANDROID_JAR="$ANDROID_HOME/platforms/android-34/android.jar"
```

Validate the resource table immediately:

```bash
aapt2 dump resources "$ANDROID_JAR" >/dev/null
```

## 3. Build without Gradle

A working minimal project needs `AndroidManifest.xml`, `res/`, `src/`, `test/`,
and a build script. Programmatic UI reduces resource risk. Keep fixed strings in
`res/values/` and add `res/values-zh-rCN/` for Chinese.

```bash
aapt2 compile --dir res -o build/resources.zip
aapt2 link -o build/base.apk -I "$ANDROID_JAR" \
  --manifest AndroidManifest.xml --java build/gen \
  --min-sdk-version 26 --target-sdk-version 34 build/resources.zip

mapfile -t SOURCES < <(find src -name '*.java' | sort)
javac -encoding UTF-8 -source 8 -target 8 -Xlint:-options \
  -bootclasspath "$ANDROID_JAR" -d build/classes \
  "${SOURCES[@]}" build/gen/<package>/R.java

dx --dex --min-sdk-version=26 \
  --output=build/classes.dex build/classes

cp build/base.apk build/unaligned.apk
( cd build && zip -q -9 unaligned.apk classes.dex )
zipalign -f 4 build/unaligned.apk build/aligned.apk
```

Sign with v2/v3. With `minSdkVersion >= 24`, v1 is unnecessary:

```bash
apksigner sign --ks keystore/debug.p12 --ks-key-alias tallydebug \
  --ks-pass pass:android --key-pass pass:android \
  --v1-signing-enabled false --v2-signing-enabled true \
  --v3-signing-enabled true --out dist/App.apk build/aligned.apk
```

See [example-build.sh](references/example-build.sh) and [troubleshooting](references/troubleshooting.md).

## 4. Test what can be tested

- Put domain logic in a plain-Java class and compile/run it on the host JVM.
  The validated example used 16 assertions for clamping, max/min, increment,
  decrement, and reset.
- Validate the manifest with `aapt2 dump badging` (package, SDK levels,
  localised labels, launchable activity).
- Verify signature with `apksigner verify --verbose --print-certs`.
- Verify 4-byte alignment with `zipalign -c -v 4`.
- Confirm `classes.dex`, `resources.arsc`, manifest, and launcher icon exist.
- Compare the final APK SHA-256 with the file actually served by the public URL.

Never call these device tests; if runtime proof is mandatory, request a real device.

## 5. Publish and prove the download

Prefer a host that explicitly permits APK uploads. In the validated run, Gofile
accepted the APK and Filebin served a direct download. Filebin rejected lowercase
`.apk` with HTTP 403 but accepted `.APK`; treat that as a host-specific quirk, not
a guarantee. Only upload your own benign build, respect the host's terms, and do
not use naming tricks to evade malware controls.

Minimum close-out:

1. Rebuild after the final code change; timestamps mean the hash can change.
2. Upload the **final** APK, source zip, and checksum file.
3. Download the public URL again and compare SHA-256 byte-for-byte.
4. Report the URL, expiry if any, APK size, SHA-256, min/target SDK, and that the
   signing certificate is a debug cert (not Play Store ready).
5. Present the local APK as a fallback so a flaky public host cannot lose the
   deliverable.

## Critical pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| `sandbox mode "workspace-write" ... no sandbox backend` | Host has no usable sandbox backend | Follow policy; use the permitted access mode rather than silently running unconfined |
| `write` reports success but files are dangling symlinks | DSH filesystem backend materialised symlinks to deleted temp dirs | `find . -type l -delete`; rewrite via shell heredoc; verify with `file`, `head`, `find -type l` |
| `Entry offset ... outside the Type's boundaries` / `entry offsets overlap actual entry data` | Old `aapt2` cannot parse the Android 35 platform resource table | Link against Platform 34, or obtain a newer aapt2 |
| `failed to load include path ...android.jar` | Wrong or incompatible platform jar | Check path and `aapt2 dump resources` |
| `dx: command not found` | Debian puts dx under `build-tools/debian`, not PATH | Use absolute path or add it to PATH |
| `package android.app does not exist` | javac used the host JDK instead of android.jar | `-bootclasspath "$ANDROID_JAR"` |
| `apksigner` says v1 false | minSdk >= 24 and v1 disabled/defaulted off | Use v2/v3; do not claim v1 |
| `Empty reply` / `503` from upload hosts | Datacenter IP or APK-type blocking | Try a host that permits APKs; verify every link |

More failures and exact messages: [references/troubleshooting.md](references/troubleshooting.md).

## Deliverable checklist

```
dist/App.apk                  signed, aligned, installable
dist/app-source.zip           manifest, res, src, test, build script, README
dist/SHA256SUMS.txt           final hashes
dist/test-results.txt         host-JVM test output
dist/verify.txt               apksigner output
dist/badging.txt              package/SDK/launcher metadata
README.md                     build, install, limitations, debug-key warning
```

Public delivery notes: [references/public-delivery.md](references/public-delivery.md).
Environment details: [references/environment.md](references/environment.md).
