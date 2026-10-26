#!/usr/bin/env bash
# Upload a built APK, the download page and the privacy policy (/privacy/) to the VPS.
# Usage: deploy/deploy.sh [path/to/app-release.apk]
# Env: LETOPIS_HOST (default root@85.137.88.33), LETOPIS_DIR (default /var/www/letopis).
set -euo pipefail

cd "$(dirname "$0")/.."
APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
HOST="${LETOPIS_HOST:-root@85.137.88.33}"
DIR="${LETOPIS_DIR:-/var/www/letopis}"

[ -f "$APK" ] || { echo "APK not found: $APK (run: flutter build apk --release)"; exit 1; }

VERSION=$(sed -n 's/^version: *//p' pubspec.yaml)
SIZE=$(awk -v b="$(wc -c < "$APK")" 'BEGIN { printf "%.1f", b / 1048576 }')
SHA=$(sha256sum "$APK" | cut -d' ' -f1)
DATE=$(date +%d.%m.%Y)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
sed -e "s/{{VERSION}}/$VERSION/" -e "s/{{SIZE}}/$SIZE/" -e "s/{{SHA256}}/$SHA/" -e "s/{{DATE}}/$DATE/" \
  deploy/index.html > "$TMP/index.html"
cp "$APK" "$TMP/letopis.apk"

# Upload under temporary names, then rename: a download in progress never sees a half-written file.
ssh "$HOST" "mkdir -p '$DIR/privacy'"
scp -q "$TMP/letopis.apk" "$HOST:$DIR/letopis.apk.new"
scp -q "$TMP/index.html" "$HOST:$DIR/index.html.new"
scp -q deploy/privacy.html "$HOST:$DIR/privacy/index.html.new"
ssh "$HOST" "cd '$DIR' && mv letopis.apk.new letopis.apk && mv index.html.new index.html && mv privacy/index.html.new privacy/index.html"

echo "Uploaded $VERSION ($SIZE MB, sha256 $SHA) to $HOST:$DIR"
