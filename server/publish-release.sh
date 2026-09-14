#!/bin/zsh
# Выложить сборки версии в /dl/ на api.amnez.online и обновить latest.json,
# по которому приложение зовёт обновиться.
#
#   zsh server/publish-release.sh 1.0.27 <run-id APK> <run-id Windows> <run-id macOS>
#
# Номера прогонов — из `gh run list -R vadoil/tunnelo --branch build`.
# Любой из трёх можно пропустить дефисом: тогда ссылка на платформу в
# latest.json остаётся прежней.
set -e

VERSION=$1; APK=$2; WIN=$3; MAC=$4
[[ -z "$VERSION" ]] && { echo "нужна версия, например 1.0.27"; exit 1; }
REPO=vadoil/tunnelo
HOST=root@78.17.33.149
DL=/var/www/dl
BASE=https://api.amnez.online/dl
TMP=$(mktemp -d)

fetch() { gh run download "$1" -R $REPO -D "$TMP/$2" >/dev/null; }
push() { scp -q "$1" "$HOST:$DL/$2.new" && ssh $HOST "mv -f $DL/$2.new $DL/$2"; echo "  $BASE/$2"; }

echo "Выкладываю $VERSION…"
ANDROID=""; WINDOWS=""; MACOS=""
if [[ -n "$APK" && "$APK" != "-" ]]; then
  fetch "$APK" apk
  push "$(find "$TMP/apk" -name 'Tunnelo-arm64.apk' | head -1)" "Tunnelo-$VERSION.apk"
  ANDROID="$BASE/Tunnelo-$VERSION.apk"
fi
if [[ -n "$WIN" && "$WIN" != "-" ]]; then
  fetch "$WIN" win
  push "$(find "$TMP/win" -name 'Tunnelo-Setup-*.exe' | head -1)" "Tunnelo-Setup-$VERSION.exe"
  WINDOWS="$BASE/Tunnelo-Setup-$VERSION.exe"
fi
if [[ -n "$MAC" && "$MAC" != "-" ]]; then
  fetch "$MAC" mac
  push "$(find "$TMP/mac" -name 'Tunnelo-macOS.zip' | head -1)" "Tunnelo-macOS-$VERSION.zip"
  MACOS="$BASE/Tunnelo-macOS-$VERSION.zip"
fi

# Старый latest.json — источник ссылок для платформ, которые не обновляли.
OLD=$(ssh $HOST "cat $DL/latest.json 2>/dev/null || echo '{}'")
/opt/homebrew/bin/python3.11 - "$VERSION" "$ANDROID" "$WINDOWS" "$MACOS" "$OLD" > "$TMP/latest.json" <<'EOF'
import json, sys, datetime
version, android, windows, macos, old = sys.argv[1:6]
try:
    prev = json.loads(old).get("downloads", {})
except Exception:
    prev = {}
major, minor, patch = (int(x) for x in version.split("."))
build = major * 10000 + minor * 100 + patch  # как в pubspec: 1.0.27+10027
downloads = {k: v for k, v in {
    "android": android or prev.get("android"),
    "windows": windows or prev.get("windows"),
    "macos": macos or prev.get("macos"),
}.items() if v}
print(json.dumps({
    "version": version,
    "build": build,
    "published": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
    "downloads": downloads,
}, ensure_ascii=False, indent=2))
EOF
push "$TMP/latest.json" latest.json
cat "$TMP/latest.json"
rm -rf "$TMP"
