# ARM64 Android CLI environment

Validated on Ubuntu 24.04.5 LTS, aarch64, Java 17.0.20, Android Platform 34,
`aapt2 2.19-debian`, `dx 10.0.0`, and `apksigner 0.9`.

## Why not Google Build-Tools

Google's Linux Build-Tools archives are normally x86_64. Running them needs
qemu or a VM. For a build-only container, Ubuntu's ARM64 packages are simpler
and fully native:

| Need | Ubuntu package / path |
|---|---|
| JDK | `openjdk-17-jdk-headless` |
| SDK layout | `android-sdk-common` |
| Build tools | `android-sdk-build-tools` |
| Dexer | `dalvik-exchange`, binary `/usr/lib/android-sdk/build-tools/debian/dx` |
| Platform jar | `/usr/lib/android-sdk/platforms/android-34/android.jar` |
| Zip / HTTP / inspection | `zip unzip curl file ca-certificates` |

`android-sdk-build-tools` installs `aapt2`, `aapt`, `apksigner`, `zipalign`, and
`aidl` under `/usr/lib/android-sdk/build-tools/debian`. The `dx` binary comes
from `dalvik-exchange` and is not automatically on PATH.

## Install

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  openjdk-17-jdk-headless android-sdk-build-tools android-sdk-common \
  dalvik-exchange curl unzip zip file ca-certificates
```

Then install Platform 34:

```bash
curl -fL -o /tmp/platform-34.zip \
  https://dl.google.com/android/repository/platform-34-ext7_r03.zip
echo "1f2e9478d6a7601425ceaa553311dc43191f103d  /tmp/platform-34.zip" \
  | sha1sum -c
rm -rf /tmp/platform34
mkdir -p /tmp/platform34
unzip -q /tmp/platform-34.zip -d /tmp/platform34
rm -rf /usr/lib/android-sdk/platforms/android-34
mv /tmp/platform34/android-34 /usr/lib/android-sdk/platforms/android-34
rm -f /tmp/platform-34.zip
```

The checksum is for `platform-34-ext7_r03.zip` at validation time. If Google
rotates the archive, read `repository2-1.xml` and update both URL and checksum.

## Environment variables

```bash
export ANDROID_HOME=/usr/lib/android-sdk
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/build-tools/debian:$PATH"
export ANDROID_JAR="$ANDROID_HOME/platforms/android-34/android.jar"
```

Put this in `/etc/profile.d/android-sdk.sh` for login shells, but make build
scripts set fallbacks themselves: non-interactive shells do not source profile.d.

## Disk and helper constraints

- The validated host had ~2 GB free. `apt` lists alone were 205 MB; run
  `apt-get clean` and `rm -rf /var/lib/apt/lists/*` afterwards.
- `python3` was absent. Do not use it for JSON parsing, HTTP serving, or checksum
  glue unless installed. Node.js existed; shell `sed`, `grep`, `cut`, `sha256sum`
  covered the build.
- `strings` was absent; use `file`, `unzip -l`, and `aapt2 dump badging` instead.
- `adb` was not installed. Building does not need it; installing/running on a
  device does.
- Keep the debug keystore (for incremental updates). Back it up with the source.

## Inspect before trusting

```bash
java -version; javac -version
aapt2 version
ls -lh "$ANDROID_JAR"
aapt2 dump resources "$ANDROID_JAR" >/dev/null && echo "resource table OK"
ls -l "$ANDROID_HOME/build-tools/debian/dx"
```

`javac` and `java` can point at different JDKs because of Debian alternatives.
Always set `JAVA_HOME` and use `$JAVA_HOME/bin/javac` / `$JAVA_HOME/bin/java` in
build scripts.
