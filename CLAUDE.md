# Tunnelo — контекст проекта

Ты работаешь над **Tunnelo** — коммерческим VPN-приложением для России.
Это форк `hiddify/hiddify-app` (Flutter + sing-box), ветка `build` от тега `v4.1.2`.

Прочитай этот файл целиком перед первым действием. Здесь то, что уже выяснено
дорогой ценой — не переоткрывай это заново.

---

## Что за продукт

Пользователь скачивает APK, открывает — и всё работает. Без регистрации,
без ввода ключей, без настроек. Внутри:

- при первом запуске приложение само активирует промокод и получает подписку
- серверы приходят списком, приложение выбирает быстрейший
- российские сайты (Ozon, Госуслуги, банки, `.ru`) идут **мимо** VPN
- заблокированное (YouTube, Telegram, Instagram) — через VPN
- есть ручное переключение сервера и ввод своего промокода

Дальше: Telegram-бот с оплатой, публикация в Google Play и App Store.

---

## Инфраструктура

| Что | Где | Доступ |
|---|---|---|
| Панель 3x-ui | `https://panel.amnez.online:54629/JHrp6hPbUORIYq4aUm` | `78.17.33.149` |
| Сервис активации | `https://api.amnez.online` | там же, systemd `tunnelo-activation`, файл `/opt/tunnelo/activation-3xui.py`, окружение `/etc/default/tunnelo-activation` |
| Узел fi-1 | `fi.amnez.online` → `217.177.33.106` | 3x-ui на `:2053` |
| Подписка | `https://panel.amnez.online/sub/{subId}` | обновление раз в 12 ч |
| Сайт tunello.online | `27.102.139.44`, `/opt/tunnelo-site`, сервис `tunnelo-site.service` | исходники в `site/`; выкат: scp app.py, templates, static/style.css + `systemctl restart tunnelo-site` (бэкап app.py.bak-дата) |
| Скачивание сборок | `https://api.amnez.online/dl/<файл>` | nginx, файлы в `/var/www/dl` на том же сервере; выкладывать `server/publish-release.sh`, он же пишет `latest.json` для проверки обновлений |

**Почта.** У хостера сервиса активации закрыт исходящий SMTP, поэтому коды
входа и письма он отправляет через сайт: `POST https://tunello.online/internal/mail`
с заголовком `X-Tunnelo-Secret` (MAIL_URL/MAIL_SECRET в
`/etc/default/tunnelo-activation`, тот же секрет в `.env` сайта). Сайт
отдаёт письмо локальному postfix, тот пересылает через Resend
(smtp.resend.com:587, ключ в /etc/postfix/sasl_passwd), домен tunello.online
в Resend подтверждён. Маршрут `/internal/mail` в site/app.py уже терялся при
рефакторинге (15.09.2026, люди не получали коды) — не удалять; проверка:
`journalctl -u tunnelo-activation | grep "письмо не ушло"`.

Сервис активации: `POST /activate {"code":"PARDAUTO","device":"<hwid>"}` →
создаёт клиента в панели на 30 дней, возвращает `{key, subscription, daysLeft, servers}`.
Повтор с того же `device` возвращает тот же ключ. Токен панели живёт только
на сервере, в APK его нет и быть не должно.

Выкат сервиса: `server/deploy.sh` (бэкап, копия, рестарт, журнал, список
кодов). Заходить по SSH ключом `~/.ssh/id_ed25519` под root.

Промокоды лежат в таблице `promos` базы сервиса, не в коде. Добавить или
поправить — на сервере, без перезапуска:
`python3 activation-3xui.py promo add КОД ДНИ [ЛИМИТ] [заметка]`, список —
`promo list`. Лимит 0 = без ограничения. Словарь `PROMO_CODES` в файле —
только стартовый посев. Коды людям передавать латиницей: поле в приложении
кириллицу отрезает (и теперь объясняет это подсказкой).

---

## Что уже сделано в коде

```
lib/features/tunnelo/
  tunnelo_activation.dart      клиент api.amnez.online, device id, хранение ключа
  tunnelo_setup_notifier.dart  автонастройка при первом запуске, RU-правила,
                               MAX вне туннеля, самолечение локального профиля
  tunnelo_theme.dart           палитра + виджет колец туннеля (CustomPainter)
  tunnelo_setup_overlay.dart   шторка первого запуска (подключена)
  promo_code_page.dart         экран промокода (кнопка «Промокод» на главной)
  tunnelo_status_card.dart     карточка подписки на главной
  vpn_conflicts.dart           поиск чужих VPN-клиентов (пакеты Android,
                               реестр и процессы Windows, /Applications)
  tunnelo_conflict_card.dart   карточка «Мешает другой VPN» на главной
lib/features/app_update/data/app_update_repository.dart
                               источник версий — https://api.amnez.online/dl/latest.json
                               (не GitHub Releases); главная зовёт проверку через 4 с
                               после старта и показывает «Обновить / Позже»
server/publish-release.sh      выложить сборки CI в /dl/ и обновить latest.json:
                               zsh server/publish-release.sh 1.0.28 <apk> <win> <mac>
lib/core/http_client/
  doh_fallback.dart            DohFallbackAdapter: при отказе системного DNS
                               резолв через DoH и запрос по IP с SNI. Через него
                               ходят и загрузчик профилей, и клиент активации
```

`home_page.dart` пропатчен: вызывает `runIfNeeded()` при старте.

**iOS: имена платформенных каналов** строятся из `SERVICE_IDENTIFIER`
(ios/Base.xcconfig), и он обязан быть `com.hiddify.app` — Dart и Android
ждут именно его. «Своё» значение = MissingPluginException(get_paths) и
вечная заставка.

**Без системного DNS резолв не отказывает, а висит** (провайдер режет
UDP/53; на AVD — ~11 с). Поэтому адаптер не ждёт «Failed host lookup», а
сам пробует резолв с лимитом 4 с и при отказе идёт через DoH. Подписка при
этом скачивается с заголовками, профиль остаётся удалённым.

Брендинг применён: имя Tunnelo, иконка, `applicationId app.tunnelo.com`.
**Внутренние** имена не менялись намеренно: `pubspec name: hiddify` (стоит в
каждом импорте) и `namespace com.hiddify.hiddify` (привязан к путям Kotlin).
Их менять = переписывать проект ради невидимых пользователю строк.

Сборка: GitHub Actions, `.github/workflows/tunnelo-apk.yml`, триггер — push
в ветку `build`. Занимает ~14 минут, артефакт `Tunnelo-APK`.

---

## Дорого добытые факты — не переоткрывать

**sing-box не поддерживает XHTTP.** `sing-box check` → `unknown transport type: xhttp`.
Это транспорт исключительно Xray. Никакой правкой параметров не исправить.

**Reality в sing-box падает** с `reality verification failed`, хотя тот же
инбаунд через xray-клиент работает. Причина — гибридный обмен ключами
X25519MLKEM768 в Xray 26.x, которого нет в REALITY-клиенте sing-box.

**Значит, для этого приложения рабочий протокол один — Hysteria2.**
На узлах ставим его. Reality и XHTTP держим только для сторонних клиентов (Happ).

**ТСПУ душит TCP с TLS-рукопожатием.** На узле fi-1: Reality давал 73%
односторонних ретрансмиссий сервер→клиент при 1.7% встречных, ClientHello
доходил, ServerHello не возвращался. UDP при этом проходит свободно —
Hysteria2 качает 24–27 МБ/с.

**Раздельная маршрутизация возможна только в клиенте.** Когда запрос дошёл
до узла, он уже прошёл через туннель — сервер не может отправить его обратно
мимо туннеля. Все правила исполняются в приложении, в конфиге sing-box.

**Правила RoscomVPN (`happ://routing/add/...`) не подходят** — это собственная
схема Happ с ключами `DirectSites`/`GlobalProxy`, sing-box их не знает.
И `.dat`-геоданные — формат xray, sing-box читает только `.srs`.

**Смена протокола инбаунда в панели молча отцепляет клиентов**: `inboundIds`
схлопывается, а ответ приходит `success: true`. После правки нужен `bulkAttach`.

**Новый узел не появляется в подписках существующих клиентов** автоматически.
Нужен проход `bulkAttach` по всей базе.

---

## Известные проблемы (в работе)

1. **Подпись APK — решено 14.09.** Release-keystore создан пользователем
   (`android/make-keystore.sh`), секреты `ANDROID_KEYSTORE_*` в репо, CI
   подписывает им (SHA-256 345f5ecd…9de9). Ключ лежит в
   `~/tunnelo-keystore/`, его потеря = невозможность обновлений.
2. **Windows: права администратора.** Адаптер wintun создаётся только с
   правами администратора, иначе ядро отвечает «configure tun interface:
   Access is denied» и «Непредвиденный сбой». Уровень requireAdministrator
   задан в `windows/runner/runner.exe.manifest` и компоновщику
   (`/MANIFESTUAC:level='requireAdministrator'`, только эта форма — составную
   с uiAccess генератор VS молча игнорирует). Проверять по манифесту готового
   exe: `grep -a requestedExecutionLevel Tunnelo.exe`. Автозапуск — задача
   планировщика (schtasks /RL HIGHEST), ярлык в автозагрузке для таких
   программ Windows не запускает. Починено в 1.0.26 (a219db80), на машине
   пользователя ещё не подтверждено.
3. **iOS-сборка в App Store не собиралась**: нужен Apple Developer
   (Team ID в ios/Base.xcconfig, DEVELOPMENT_TEAM пустой). Симулятор
   работает локально, см. память tunnelo-ios-simulator.

Закрыто: YouTube/Google (IPv6, 01.09), MAX вне туннеля, шторка и
промокод подключены, «Подписка не активна» при отказе DNS (12.09),
ребрендинг всех экранов и заставок Android/iOS сверен (14.09), iOS
доходит до онбординга в симуляторе (14.09).

## Как работать

- Ветка `build`. Правки → `git push` → сборка стартует сама.
- Перед коммитом: `flutter analyze` должен быть чистым.
- Не менять логику ради красоты — сначала работает, потом красиво.
- Если сборка упала: `gh run view --log-failed`, чинить, пушить снова.
- Тексты в интерфейсе — по-русски, в тоне «спокойно и по делу»:
  активное «Активировать», а не «Отправить»; ошибка объясняет, что делать.

## Чего не делать

- Не менять `pubspec name` и `namespace` — см. выше почему.
- Не добавлять Reality и XHTTP как рабочие каналы для этого приложения.
- Не выносить токен панели в код приложения.
- Не трогать чужую панель `vpnnetus.mooo.com` — она не наша.
