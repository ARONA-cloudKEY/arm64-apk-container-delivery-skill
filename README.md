# android-apk-container-delivery

A DSH skill for building, testing, signing, verifying, and publicly delivering
an Android APK in a headless ARM64 Linux container—without Gradle, Android
Studio, an emulator, or a VM.

## Install

Already installed for this user at:

```
~/.dsh/skills/android-apk-container-delivery/
```

To install the packaged copy on another DSH host:

```bash
mkdir -p ~/.dsh/skills
unzip android-apk-container-delivery.skill.zip -d /tmp/skill-unpack
cp -a /tmp/skill-unpack/android-apk-container-delivery ~/.dsh/skills/
```

The skill watcher discovers `<dshHome>/skills/<name>/SKILL.md`; a new session or
the next model step should show it in the catalog.

## Contents

| Path | Purpose |
|---|---|
| `SKILL.md` | Core procedure and critical pitfalls |
| `references/environment.md` | ARM64 apt/JDK/Platform 34 setup |
| `references/example-build.sh` | Copyable no-Gradle build/sign script |
| `references/public-delivery.md` | Gofile/Filebin flow and link verification |
| `references/troubleshooting.md` | Exact errors and fixes |
| `scripts/install-android-sdk-arm64.sh` | Bootstrap the CLI toolchain |
| `scripts/verify-apk.sh` | Signature/alignment/manifest/checksum check |
