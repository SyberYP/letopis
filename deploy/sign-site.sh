#!/usr/bin/env bash
# Re-sign a release APK for the download site with a key-rotation proof (APK Signature Scheme v3).
# Phones that still have a build signed with the retired personal key (letopis-dev.jks, before 1.1.1)
# accept it as an update and keep their data. The old key can no longer update those phones
# afterwards (the lineage gives it no rollback right).
# Usage: deploy/sign-site.sh <in.apk> <out.apk>   (needs android/key.properties and Android build-tools)
set -euo pipefail
cd "$(dirname "$0")/.."
IN="$1"; OUT="$2"

SDK="${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}"
APKSIGNER=$(ls "$SDK"/build-tools/*/apksigner* 2>/dev/null | grep -E 'apksigner(\.bat)?$' | sort -V | tail -1)
[ -n "$APKSIGNER" ] || { echo "apksigner not found under $SDK/build-tools"; exit 1; }

prop() { sed -n "s/^$1=//p" android/key.properties | tr -d '\r'; }
[ -f android/key.properties ] || { echo "android/key.properties missing (see docs/DEVELOPMENT.md, «Подпись»)"; exit 1; }
export LETOPIS_KS_PASS LETOPIS_KEY_PASS
LETOPIS_KS_PASS=$(prop storePassword)
LETOPIS_KEY_PASS=$(prop keyPassword)

# v3 only (Android 9+): v1/v2 would have to be signed by the oldest key in the lineage.
"$APKSIGNER" sign \
  --ks "$(prop storeFile)" --ks-key-alias "$(prop keyAlias)" \
  --ks-pass env:LETOPIS_KS_PASS --key-pass env:LETOPIS_KEY_PASS \
  --lineage deploy/signing-lineage.bin --rotation-min-sdk-version 28 --min-sdk-version 28 \
  --v1-signing-enabled false --v2-signing-enabled false --v3-signing-enabled true \
  --out "$OUT" "$IN"
"$APKSIGNER" verify --min-sdk-version 28 "$OUT"
echo "Signed $OUT (upload key + rotation from the personal key)"
