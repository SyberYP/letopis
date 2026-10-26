#!/usr/bin/env bash
# Build the download-site APK (with the "Check for updates" button), re-sign it with the key
# rotation proof and upload it with the download page, version.json and the privacy policy.
# Usage: deploy/deploy.sh            builds with --dart-define=LETOPIS_CHANNEL=site
#        deploy/deploy.sh some.apk   uploads a ready APK (must be built with that define)
# Store builds are separate: `flutter build apk|appbundle --release` without the define.
# Env: LETOPIS_HOST (default root@85.137.88.33), LETOPIS_DIR (default /var/www/letopis).
set -euo pipefail

cd "$(dirname "$0")/.."
APK="${1:-}"
HOST="${LETOPIS_HOST:-root@85.137.88.33}"
DIR="${LETOPIS_DIR:-/var/www/letopis}"

if [ -z "$APK" ]; then
  flutter build apk --release --dart-define=LETOPIS_CHANNEL=site
  APK=build/app/outputs/flutter-apk/app-release.apk
fi
[ -f "$APK" ] || { echo "APK not found: $APK"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
deploy/sign-site.sh "$APK" "$TMP/letopis.apk"
VERSION=$(sed -n 's/^version: *//p' pubspec.yaml | tr -d '\r')
NAME=${VERSION%%+*}
BUILD=${VERSION##*+}
echo "{\"version\": \"$NAME\", \"build\": $BUILD}" > "$TMP/version.json"
SIZE=$(awk -v b="$(wc -c < "$TMP/letopis.apk")" 'BEGIN { printf "%.1f", b / 1048576 }')
SHA=$(sha256sum "$TMP/letopis.apk" | cut -d' ' -f1)
DATE=$(date +%d.%m.%Y)
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SIZE}}/$SIZE/" -e "s/{{SHA256}}/$SHA/" -e "s/{{DATE}}/$DATE/" \
  deploy/index.html > "$TMP/index.html"

# Upload under temporary names, then rename: a download in progress never sees a half-written file.
ssh "$HOST" "mkdir -p '$DIR/privacy'"
scp -q "$TMP/letopis.apk" "$HOST:$DIR/letopis.apk.new"
scp -q "$TMP/index.html" "$HOST:$DIR/index.html.new"
scp -q "$TMP/version.json" "$HOST:$DIR/version.json.new"
scp -q deploy/privacy.html "$HOST:$DIR/privacy/index.html.new"
ssh "$HOST" "cd '$DIR' && mv letopis.apk.new letopis.apk && mv index.html.new index.html && mv version.json.new version.json && mv privacy/index.html.new privacy/index.html"

echo "Uploaded $VERSION ($SIZE MB, sha256 $SHA) to $HOST:$DIR"
