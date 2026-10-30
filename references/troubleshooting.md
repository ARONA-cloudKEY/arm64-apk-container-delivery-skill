# Troubleshooting and verified fixes

## Sandbox refuses to start a command

Message:

```
sandbox mode "workspace-write" is requested but no sandbox backend is usable
```

The host has no bwrap/Landlock/seatbelt backend. This is an environment issue,
not a project failure. Follow the current approval policy. If full access is
permitted, retry only the specific command with that mode; do not globally
disable security controls on your own.

## Files are dangling symlinks

Observed in the DSH container: `write` returned success, but project files were
symlinks to temp directories that no longer existed, so `head`/`javac` failed
with ENOENT.

Detection:

```bash
find . -type l -print
file AndroidManifest.xml
head -1 AndroidManifest.xml
```

Recovery:

```bash
find . -type l -delete
# Recreate real files with shell heredocs, then check:
find . -type l -print   # must be empty
file AndroidManifest.xml
```

Never assume a successful tool response means bytes reached disk. This is a
harness-specific hazard; verify before a long build.

## aapt2 cannot read the Android 35 platform jar

Messages:

```
LoadedArsc.cpp:94 RES_TABLE_TYPE_TYPE entry offsets overlap actual entry data.
ApkAssets.cpp:149 Failed to load resources table in APK '.../android-35/android.jar'.
error: failed to load include path .../android-35/android.jar.
```

`aapt2 2.19-debian` cannot parse the Android 15 resource table. Use Platform 34
for resource linking, or install a newer aapt2 built for ARM64. Confirm with:

```bash
aapt2 dump resources "$ANDROID_JAR" >/dev/null
```

Do not simply point at Platform 35 and ignore the error: the build will fail at
`aapt2 link`. API 34 is sufficient for `minSdk 26`, `targetSdk 34`, adaptive
icons, vector drawables, and the framework APIs used by a simple offline app.

## `dx: command not found`

`dx` is not on PATH after installing `dalvik-exchange`. Use:

```bash
/usr/lib/android-sdk/build-tools/debian/dx --dex ...
```

or prepend `/usr/lib/android-sdk/build-tools/debian` to PATH. `dx` supports Java
8 class files; compile with `-source 8 -target 8`.

## javac cannot find Android classes

`package android.app does not exist` means javac used the host JDK. Compile
against `android.jar`:

```bash
javac -source 8 -target 8 -bootclasspath "$ANDROID_JAR" ...
```

Do not use `--release 8` together with `-bootclasspath`; javac 17 rejects that
combination.

## aapt2 link fails after javac succeeds

Check that `--java build/gen` was supplied and that the generated `R.java` is in
the javac source list. The path is package-specific, for example
`build/gen/io/github/nnn/tally/R.java`. Also check `res/` was compiled first.

## APK signs but v1 verification is false

`apksigner` reports v1 false when v1 is disabled or unnecessary for
`minSdkVersion >= 24`. v2 and v3 are sufficient for Android 7+. Explicitly pass:

```bash
--v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true
```

Do not promise "v1/v2/v3" in documentation if the verifier says v1 false. If a
v4 `.idsig` file appears, it is a sidecar and not needed for ordinary APK
installation.

## Public upload host returns empty reply / 403 / 503

The validated container saw:

- catbox: HTTP/2 `PROTOCOL_ERROR`, then empty reply over HTTP/1.1
- 0x0.st: 503
- pixeldrain / transfer.sh: connection reset or timeout
- transfer.archivete.am: upload returned a URL, but downloads returned a 403 JPEG
- uguu / qu.ax: 415 or 400 "file type not allowed" for APK
- Filebin: 403 for `App.apk`; accepted `App.APK`
- Gofile: upload API worked

These are host/CDN/IP policies, not proof the APK is broken. Try a host that
explicitly allows APKs, and always test the exact public URL. Do not use a
filename trick to evade a malware control; only use a case variant for your own
benign, source-available build if the host's terms allow it.

## Rebuilt APK has a new hash

Zip entry timestamps and signing can change the bytes even when source is
identical. After the final edit, rebuild, recompute SHA-256, and re-upload that
exact file. Earlier uploads are stale even if the version name is unchanged.

## Android 15 edge-to-edge

With `targetSdk 35`, Android 15 draws content under system bars. If you keep
`targetSdk 34`, do not apply API-35-only inset padding as well, or you get double
padding. If you target 35, call `setFitsSystemWindows(true)` on the root or apply
window insets once. Test on a device; static checks cannot prove layout.

## Large circular button shows square ripple corners

`new RippleDrawable(color, content, null)` has no mask, so the ripple fills the
whole rectangular bounds. Supply an oval mask for a circle, or a rounded rect
mask for a pill:

```java
GradientDrawable mask = new GradientDrawable();
mask.setShape(GradientDrawable.OVAL);
mask.setColor(0xFFFFFFFF);
button.setBackground(new RippleDrawable(
    ColorStateList.valueOf(0x40FFFFFF), content, mask));
```
