#!/usr/bin/env bash
# =============================================================================
#  Tunnelo — брендирование форка hiddify-app
#
#  Запуск ИЗ КОРНЯ склонированного форка:
#      bash tunnelo-rebrand.sh
#
#  Что меняет:
#    1. applicationId  app.hiddify.com  ->  app.tunnelo.com
#    2. android:label  Hiddify          ->  Tunnelo
#    3. CFBundleDisplayName (iOS)       ->  Tunnelo
#    4. Constants.appName + ссылки на свои
#    5. Имена артефактов сборки в CI
#    6. Иконки (если рядом лежит папка tunnelo-icons/)
#
#  Что НЕ трогает намеренно:
#    - pubspec.yaml -> name: hiddify   (это имя dart-пакета, оно в каждом импорте;
#      менять = переписывать весь проект, пользователю оно не видно)
#    - namespace com.hiddify.hiddify   (завязан на Kotlin-пакеты и путь к классам)
# =============================================================================
set -euo pipefail

APP_NAME="Tunnelo"
APP_ID="app.tunnelo.com"
GH_USER="vadoil"
GH_REPO="tunnelo"
SITE="https://tunnelo.app"
SUB_DOMAIN="panel.amnez.online"   # позже поменять на свой домен

[[ -f pubspec.yaml ]] || { echo "Запускайте из корня репозитория!"; exit 1; }

echo "==> [1/6] applicationId"
sed -i.bak "s|applicationId \"app.hiddify.com\"|applicationId \"${APP_ID}\"|" android/app/build.gradle

echo "==> [2/6] Отображаемое имя (Android)"
sed -i.bak "s|android:label=\"Hiddify\"|android:label=\"${APP_NAME}\"|" android/app/src/main/AndroidManifest.xml

echo "==> [3/6] Отображаемое имя (iOS/macOS)"
sed -i.bak "s|<string>Hiddify</string>|<string>${APP_NAME}</string>|" ios/Runner/Info.plist
[[ -f macos/Runner/Configs/AppInfo.xcconfig ]] && \
  sed -i.bak "s|PRODUCT_NAME = Hiddify|PRODUCT_NAME = ${APP_NAME}|" macos/Runner/Configs/AppInfo.xcconfig || true

echo "==> [4/6] Constants.dart"
cat > lib/core/model/constants.dart.head <<EOF
abstract class Constants {
  static const appName = "${APP_NAME}";
  static const githubUrl = "https://github.com/${GH_USER}/${GH_REPO}";
  static const licenseUrl = "https://github.com/${GH_USER}/${GH_REPO}?tab=License-1-ov-file#readme";
  static const githubReleasesApiUrl = "https://api.github.com/repos/${GH_USER}/${GH_REPO}/releases";
  static const githubLatestReleaseUrl = "https://github.com/${GH_USER}/${GH_REPO}/releases/latest";
  static const appCastUrl = "https://raw.githubusercontent.com/${GH_USER}/${GH_REPO}/main/appcast.xml";
  static const telegramChannelUrl = "https://t.me/tunnelo";
  static const privacyPolicyUrl = "${SITE}/privacy";
  static const termsAndConditionsUrl = "${SITE}/terms";
  static const cfWarpPrivacyPolicy = "https://www.cloudflare.com/application/privacypolicy/";
  static const cfWarpTermsOfService = "https://www.cloudflare.com/application/terms/";

  /// Подписка, которая подставляется при первом запуске.
  /// {key} заменяется на код пользователя.
  static const defaultSubscriptionTemplate = "https://${SUB_DOMAIN}/api/sub/{key}";
  /// Списки RU-сайтов, которые идут МИМО VPN.
  static const ruDirectDomainsUrl = "https://${SUB_DOMAIN}/lists/amnezia.json";
  static const ruDirectIpsUrl = "https://${SUB_DOMAIN}/lists/amnezia-ip-lite.json";
}
EOF
python3 - <<'PY'
import re, io
src = open('lib/core/model/constants.dart', encoding='utf-8').read()
head = open('lib/core/model/constants.dart.head', encoding='utf-8').read()
# заменяем только блок abstract class Constants {...}
new = re.sub(r'abstract class Constants \{.*?\n\}\n', head, src, count=1, flags=re.S)
open('lib/core/model/constants.dart','w',encoding='utf-8').write(new)
print("   constants.dart обновлён")
PY
rm -f lib/core/model/constants.dart.head

echo "==> [5/6] Имена артефактов в CI"
sed -i.bak \
  -e "s|Hiddify-Android|${APP_NAME}-Android|g" \
  -e "s|Hiddify-Windows|${APP_NAME}-Windows|g" \
  -e "s|Hiddify-MacOS|${APP_NAME}-MacOS|g" \
  -e "s|Hiddify-iOS|${APP_NAME}-iOS|g" \
  -e "s|Hiddify-Linux|${APP_NAME}-Linux|g" \
  -e "s|Hiddify-Debian|${APP_NAME}-Debian|g" \
  .github/workflows/build.yml

echo "==> [6/6] Иконки"
if [[ -d tunnelo-icons ]]; then
  command -v convert >/dev/null || { echo "   нужен imagemagick: apt install imagemagick"; exit 1; }
  declare -A SZ=( [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192 )
  for d in "${!SZ[@]}"; do
    px=${SZ[$d]}
    dir="android/app/src/main/res/mipmap-${d}"
    mkdir -p "$dir"
    convert tunnelo-icons/tunnelo_icon_1024.png -resize ${px}x${px} "$dir/ic_launcher.webp"
    convert tunnelo-icons/tunnelo_icon_round_1024.png -resize ${px}x${px} "$dir/ic_launcher_round.webp"
  done
  echo "   mipmap обновлены"
  echo "   ! adaptive-icon (drawable/ic_launcher_foreground.xml) — векторный,"
  echo "     его правим отдельно, см. инструкцию"
else
  echo "   папки tunnelo-icons/ нет — иконки пропущены"
fi

find . -name "*.bak" -delete
cat <<EOF

=============================================================================
 Брендинг применён.

 Проверьте:
   grep -n applicationId android/app/build.gradle
   grep -n 'android:label' android/app/src/main/AndroidManifest.xml
   grep -n appName lib/core/model/constants.dart

 Дальше:
   git add -A && git commit -m "rebrand to ${APP_NAME}" && git push
   Затем GitHub -> Actions -> Build APK -> Run workflow
=============================================================================
EOF
