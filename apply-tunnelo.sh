#!/usr/bin/env bash
# =============================================================================
#  Tunnelo: автоактивация + RU-маршрутизация + автовыбор сервера
#
#  Запуск ИЗ КОРНЯ репозитория tunnelo (ветка build):
#      bash apply-tunnelo.sh
#
#  Требует рядом папку tunnelo-dart/ с тремя .dart-файлами (из архива).
# =============================================================================
set -euo pipefail

[[ -f pubspec.yaml ]] || { echo "Запускайте из корня репозитория tunnelo"; exit 1; }
[[ -d tunnelo-dart ]] || { echo "Нет папки tunnelo-dart/ — распакуйте архив"; exit 1; }

echo "==> [1/3] Файлы Tunnelo"
mkdir -p lib/features/tunnelo
cp tunnelo-dart/tunnelo_activation.dart      lib/features/tunnelo/
cp tunnelo-dart/tunnelo_setup_notifier.dart  lib/features/tunnelo/
cp tunnelo-dart/tunnelo_theme.dart           lib/features/tunnelo/
cp tunnelo-dart/tunnelo_setup_overlay.dart   lib/features/tunnelo/
cp tunnelo-dart/promo_code_page.dart         lib/features/tunnelo/
echo "    lib/features/tunnelo/ — 5 файлов"

echo "==> [2/3] Автозапуск настройки на домашнем экране"
python3 - <<'PY'
import re
f = 'lib/features/home/widget/home_page.dart'
s = open(f, encoding='utf-8').read()

if 'tunnelo_setup_notifier' in s:
    print("    уже подключено")
else:
    # импорт
    s = s.replace(
        "import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';",
        "import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';\n"
        "import 'package:hiddify/features/tunnelo/tunnelo_setup_notifier.dart';",
        1,
    )
    # хук: один раз при первом построении экрана
    anchor = "    final activeProfile = ref.watch(activeProfileProvider);"
    hook = anchor + """

    // Tunnelo: при первом запуске сами активируем промокод,
    // подтягиваем серверы и включаем RU-маршрутизацию.
    useEffect(() {
      Future.microtask(
        () => ref.read(tunneloSetupProvider.notifier).runIfNeeded(),
      );
      return null;
    }, const []);"""
    if anchor not in s:
        raise SystemExit("!! не нашёл точку вставки в home_page.dart — вставьте вручную")
    s = s.replace(anchor, hook, 1)

    # useEffect живёт во flutter_hooks
    if "package:flutter_hooks/flutter_hooks.dart" not in s:
        s = s.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\nimport 'package:flutter_hooks/flutter_hooks.dart';",
            1,
        )
    open(f, 'w', encoding='utf-8').write(s)
    print("    home_page.dart: добавлен runIfNeeded()")
PY

echo "==> [3/3] Автовыбор быстрейшего сервера по умолчанию"
python3 - <<'PY'
import glob, re
# в hiddify режим выбора прокси хранится в настройках; ищем дефолт
hits = []
for f in glob.glob('lib/features/**/*.dart', recursive=True):
    s = open(f, encoding='utf-8', errors='ignore').read()
    if 'urltest' in s.lower() or 'ProxyMode' in s:
        hits.append(f)
if hits:
    print("    файлы с настройкой режима прокси:")
    for h in hits[:6]:
        print("      ", h)
    print("    ! включите 'auto' (urltest) в UI: Прокси → группа → Auto")
else:
    print("    ! автовыбор включается в UI: Прокси → группа → Auto")
PY

cat <<'EOF'

=============================================================================
 Готово. Что сделано:

  lib/features/tunnelo/tunnelo_activation.dart      — клиент api.amnez.online
  lib/features/tunnelo/tunnelo_setup_notifier.dart  — автонастройка + RU-правила
  lib/features/tunnelo/promo_code_page.dart         — экран ввода промокода
  home_page.dart                                    — вызов runIfNeeded()

 При первом запуске приложение:
   1. добавит правила: реклама → block, локалка и российские сайты → direct
   2. активирует промокод PARDAUTO
   3. подтянет подписку со всеми серверами

 Дальше:
   flutter pub get
   git add -A && git commit -m "Tunnelo: auto activation + RU routing" && git push

 Сборка запустится сама (ветка build в триггерах workflow).
=============================================================================
EOF
