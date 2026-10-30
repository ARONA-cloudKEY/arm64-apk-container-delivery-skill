# Public APK delivery and verification

## Rules

- Upload only your own build; include source and checksum when possible.
- Read the host's terms. Do not use extension-case tricks to evade malware
  scanning. A benign, source-available debug APK is different from a hidden
  payload.
- The upload response is not proof. Download the public URL again and compare
  SHA-256 with the local file.
- Public links expire. Record the expiry and present the local artifact too.

## Gofile (worked in validation)

Upload:

```bash
curl -fL --http1.1 -A 'Mozilla/5.0' \
  -F 'file=@dist/App.apk;type=application/vnd.android.package-archive;filename=App.apk' \
  https://upload.gofile.io/uploadfile
```

The JSON response contains `downloadPage`, `parentFolder`, `guestToken`, `md5`,
`size`, and `name`. Compare `md5` with `md5sum dist/App.apk`.

To add source and checksums to the same share folder, use the returned token and
folder id:

```bash
curl -fL --http1.1 \
  -F "token=$TOKEN" -F "folderId=$FOLDER" \
  -F 'file=@dist/app-source.zip;filename=app-source.zip' \
  https://upload.gofile.io/uploadfile
```

The page is a JavaScript app; HTTP 200 only proves the page exists. For a
download-proof, use a direct-download host or a browser; do not claim a direct
file URL from a page response.

## Filebin (direct, with a case quirk)

Observed in validation:

- `POST /bin/App.apk` -> HTTP 403 (extension filtered)
- `POST /bin/App.APK` -> HTTP 201
- response includes `sha256`, `expired_at`, `content-type`
- `GET /bin/App.APK` -> 302 to a presigned S3 URL; `curl -L` returns the APK

Example:

```bash
BIN="myapp-$(date +%s)"
SHA=$(sha256sum dist/App.apk | cut -d' ' -f1)
curl -sS --http1.1 -X POST \
  -H 'Content-Type: application/octet-stream' \
  -H "Content-SHA256: $SHA" \
  --data-binary @dist/App.apk \
  "https://filebin.net/$BIN/App.APK"
```

Lock the bin after uploading all files:

```bash
curl -sS -X PUT "https://filebin.net/$BIN"
# -> Bin locked successfully.
```

Verify exactly what users will fetch:

```bash
curl -sSL --http1.1 --max-time 60 \
  "https://filebin.net/$BIN/App.APK" -o /tmp/downloaded.apk
sha256sum /tmp/downloaded.apk
cmp /tmp/downloaded.apk dist/App.apk
```

The case trick is a host-specific filter behavior, not a general standard. Check
the current policy before using it. Prefer Gofile or another host that allows APKs
when one is available.

## Delivery summary

Report:

```
URL:             ...
Expires:         ... (if known)
APK size:        ... bytes
SHA-256:         ...
Package:         ...
minSdk/target:   ...
Signature:       debug cert, v2/v3, not Play Store ready
Verification:    public download re-fetched; hash matched
Limitation:      not launched on a device/emulator
```

Also present the local APK and source zip as fallback downloads.
