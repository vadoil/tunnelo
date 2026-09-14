#!/bin/zsh
# Создаёт release-ключ подписи Tunnelo для Android и кладёт его в GitHub Secrets.
# Запускать один раз, руками, в Терминале:  zsh android/make-keystore.sh
#
# Почему руками: ключ и пароль — секреты, ассистент их создавать не должен.
# Ключ живёт в ~/tunnelo-keystore/, пароль — в ~/tunnelo-keystore/ПРОЧТИ.txt.
# Потеря ключа = невозможность обновить приложение у пользователей и в Google Play.
set -e

KEYTOOL=/opt/homebrew/opt/openjdk@17/bin/keytool
DIR="$HOME/tunnelo-keystore"
JKS="$DIR/tunnelo-release.jks"
ALIAS=tunnelo
REPO=vadoil/tunnelo

mkdir -p "$DIR"
chmod 700 "$DIR"

if [[ -f "$JKS" ]]; then
  echo "Ключ уже есть: $JKS — не перезаписываю."
  PASS=$(grep 'Пароль' "$DIR/ПРОЧТИ.txt" | awk '{print $NF}')
else
  PASS=$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-28)
  "$KEYTOOL" -genkeypair -v \
    -keystore "$JKS" -alias "$ALIAS" \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -storepass "$PASS" -keypass "$PASS" \
    -dname "CN=Tunnelo, O=Tunnelo, C=RU"
  cat > "$DIR/ПРОЧТИ.txt" <<EOF
Ключ подписи Tunnelo для Android (release keystore). Создан $(date +%d.%m.%Y).
Этим ключом подписываются все сборки APK из CI.

Файл:   tunnelo-release.jks
Alias:  $ALIAS
Пароль хранилища и ключа: $PASS

ХРАНИТЬ НАДЁЖНО, сделать резервную копию (облако, флешка).
Потеря ключа = невозможность обновить приложение у пользователей и в Google Play.
Никому не передавать, в git не класть.

Те же значения лежат в GitHub Secrets репозитория $REPO:
ANDROID_KEYSTORE_B64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD.
EOF
  chmod 600 "$DIR"/*
  echo "Ключ создан: $JKS"
fi

echo "Кладу секреты в GitHub ($REPO)…"
base64 -i "$JKS" | tr -d '\n' | gh secret set ANDROID_KEYSTORE_B64 -R "$REPO"
printf '%s' "$PASS"  | gh secret set ANDROID_KEYSTORE_PASSWORD -R "$REPO"
printf '%s' "$ALIAS" | gh secret set ANDROID_KEY_ALIAS -R "$REPO"
printf '%s' "$PASS"  | gh secret set ANDROID_KEY_PASSWORD -R "$REPO"
gh secret list -R "$REPO"

echo
echo "Отпечаток ключа (пригодится для Google Play):"
"$KEYTOOL" -list -v -keystore "$JKS" -alias "$ALIAS" -storepass "$PASS" | grep -E 'SHA1:|SHA256:'
echo
echo "Готово. Резервную копию папки $DIR сделайте прямо сейчас."
