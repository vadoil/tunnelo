# -*- coding: utf-8 -*-
"""Языки сайта.

Русский — основной: продукт для России. Остальные восемь добавлены 16.09.2026,
потому что приложением пользуются не только по-русски, и человек, попавший на
сайт из Еревана или Ташкента, должен прочитать про раздельную маршрутизацию на
своём языке, а не догадываться по картинкам.

Юридические документы (оферта, условия возврата, обработка данных, реквизиты)
остаются только на русском: это документы по российскому праву, и перевод в них
не имеет силы — на них ведёт отдельная строка «Документы на русском языке».

Строка, которой нет в переводе, берётся из русского: пропуск выглядит как
русская фраза среди чужих, а не как пустое место.
"""
import os

# Порядок в переключателе: русский, английский, дальше по алфавиту названий.
LANGS = [
    ("ru", "Русский"),
    ("en", "English"),
    ("az", "Azərbaycan"),
    ("hy", "Հայերեն"),
    ("ka", "ქართული"),
    ("kk", "Қазақша"),
    ("ky", "Кыргызча"),
    ("tg", "Тоҷикӣ"),
    ("uz", "Oʻzbekcha"),
]
CODES = [c for c, _ in LANGS]
DEFAULT = "ru"
COOKIE = "tunnelo_lang"

RU = {
    # --- шапка и подвал ---
    "nav_plans": "Тарифы",
    "nav_contacts": "Контакты",
    "nav_cabinet": "Кабинет",
    "cabinet_title": "Личный кабинет",
    "doc_offer": "Договор оферты",
    "doc_terms": "Условия и возврат",
    "doc_privacy": "Обработка данных",
    "doc_contacts": "Контакты",
    "docs_ru_note": "Документы — на русском языке.",
    "foot_about": "Сервис умной маршрутизации трафика.",
    "foot_support": "Поддержка",
    "foot_docs": "Документы",
    "foot_doc_offer": "Договор оферты",
    "foot_doc_terms": "Возврат и отмена",
    "foot_doc_privacy": "Персональные данные",
    "foot_doc_contacts": "Реквизиты",
    "foot_pay": "Оплата",
    "foot_pay_note": "Платежи проводит сертифицированный платёжный сервис. "
                     "Реквизиты карты к нам не попадают.",
    "foot_rights": "Все права защищены.",

    # --- первый экран ---
    "hero_badge": "Умная маршрутизация: каждому сайту — свой путь",
    "hero_title_1": "Зарубежные сервисы",
    "hero_title_2": "и российские — вместе",
    "hero_p1": "Обычный VPN отправляет через себя весь трафик — и банк начинает "
               "требовать подтверждений, маркетплейс показывает чужие цены, "
               "государственные сервисы работают со сбоями. Приходится включать и "
               "выключать его по десять раз на дню.",
    "hero_p2_b": "Tunnelo разделяет трафик сам.",
    "hero_p2": "Зарубежные сервисы идут через туннель, российские — напрямую. "
               "Одновременно, без переключений.",
    "hero_cta_plans": "Выбрать тариф",
    "hero_cta_how": "Как это работает",
    "hero_note": "Банк, Госуслуги и маркетплейсы работают как обычно. "
                 "YouTube и Telegram — как будто границ нет. Одновременно.",
    "hero_fox_alt": "Лис Tunnelo с фонарём — свет в конце туннеля",

    # --- как это работает ---
    "how_title": "Как это работает",
    "how_sub": "Обычный VPN гонит через себя всё подряд — и банки начинают "
               "требовать подтверждения, а маркетплейсы показывают чужие цены. "
               "Tunnelo разделяет трафик.",
    "flow_device": "Ваше устройство",
    "flow_brand_1": "Tunnelo смотрит,",
    "flow_brand_2": "куда вы идёте",
    "flow_direct_tag": "Российское — напрямую",
    "flow_direct_why": "Сайт видит ваш обычный адрес. Банк не просит подтверждений, "
                       "маркетплейс показывает ваши цены, Госуслуги пускают.",
    "flow_tunnel_tag": "Зарубежные сервисы — через туннель",
    "flow_tunnel_why": "Открывается с зарубежного адреса, соединение стабильно. "
                       "Переключать ничего не нужно — обе дороги работают одновременно.",

    # --- сравнение ---
    "cmp_bad_h": "Обычный VPN",
    "cmp_good_h": "Tunnelo",
    "cmp_youtube": "YouTube работает",
    "cmp_bank_bad": "банк требует подтверждений",
    "cmp_bank_good": "банк работает",
    "cmp_shop_bad": "Ozon показывает чужие цены",
    "cmp_shop_good": "Ozon показывает ваши цены",
    "cmp_gov_bad": "Госуслуги не пускают",
    "cmp_gov_good": "Госуслуги пускают",
    "cmp_bad_f": "и так каждый раз: включил — выключил",
    "cmp_good_f": "включили один раз и забыли",

    # --- устройства ---
    "dev_title": "Одна подписка — все устройства",
    "dev_text": "Телефон, компьютер и планшет. Приложение одинаковое везде: "
                "поставили, нажали одну кнопку — работает.",

    # --- карточки ---
    "card1_h": "Ничего не нужно настраивать",
    "card1_p": "Ни ключей, ни выбора серверов. Установили, вошли, "
               "нажали кнопку — всё уже готово.",
    "card2_h": "Банки и госуслуги не ругаются",
    "card2_p": "Российские сервисы видят ваш обычный адрес. Вход проходит с первого "
               "раза, без бесконечных подтверждений.",
    "card3_h": "Скорость, а не просто соединение",
    "card3_p": "Современный протокол поверх UDP держит высокую скорость: видео идёт "
               "в качестве, а не в трёхстах пикселях с паузами.",

    # --- тарифы ---
    "plan_dev_1": "1 устройство",
    "plan_dev_2": "2 устройства",
    "plans_title": "Тарифы",
    "plans_sub": "При оплате за год — на треть дешевле",
    "plans_per_month": "₽ / мес",
    "plans_or_year": "или {year} ₽ за год — это {per} ₽ в месяц",
    "plans_or_year_short": "или {year} ₽ за год",
    "plans_btn_year": "На год",
    "plans_btn_month": "На месяц",

    # --- кабинет ---
    "cab_login_h": "Вход",
    "cab_login_sub": "Логин и пароль приходят письмом — при оплате или при первом "
                     "входе по почте. Подписка живёт на аккаунте: сменили телефон, "
                     "вошли и продолжили.",
    "cab_login_ph": "Логин или почта",
    "cab_pass_ph": "Пароль",
    "cab_enter": "Войти",
    "cab_forgot_link": "Забыли пароль?",
    "cab_forgot_tail": "Пришлём ссылку на почту.",
    "cab_or": "или",
    "cab_bymail_note": "Первый раз или пароля ещё нет — войдите по почте, пришлём "
                       "код, а вместе с ним заведём логин и пароль.",
    "cab_bymail_btn": "Прислать код на почту",
    "cab_code_sent": "Отправили код на {email}. Он действует 15 минут.",
    "cab_code_ph": "000000",
    "cab_code_spam": "Письмо не пришло? Загляните в «Спам» или",
    "cab_code_other": "попробуйте другой адрес",
    "cab_sub_h": "Ваша подписка",
    "cab_exit": "выйти",
    "cab_state": "Состояние",
    "cab_state_on": "активна",
    "cab_state_off": "истекла",
    "cab_left": "Осталось",
    "cab_days": "дн.",
    "cab_devices": "Устройства",
    "cab_of": "из",
    "cab_ref_code": "Код приглашения",
    "cab_invited": "Приглашено",
    "cab_bonus": "начислено",
    "cab_key_h": "Код переноса",
    "cab_key_note": "Введите его в приложении на втором устройстве — "
                    "откройте «Промокод» и вставьте.",
    "cab_extend": "Продлить",
    "cab_payments": "Платежи",
    "cab_paid_msg": "Оплачено. Дни появятся в течение минуты — обновите страницу.",
    "cab_creds_h": "Ваш логин и пароль",
    "cab_creds_note": "Этой парой вы входите в приложение и сюда. Мы отправили её "
                      "письмом — но лучше сохраните прямо сейчас.",
    "cab_pw_h": "Пароль",
    "cab_pw_current": "Текущий пароль",
    "cab_pw_new": "Новый пароль",
    "cab_pw_again": "Ещё раз",
    "cab_pw_btn": "Сменить пароль",
    "cab_pw_ok": "Пароль изменён. Остальные входы оборвались.",
    "cab_pw_mismatch": "Пароли не совпали — введите одинаковые.",
    "cab_pw_fail": "Текущий пароль не подошёл.",

    # --- забыли пароль / новый пароль ---
    "forgot_h": "Забыли пароль",
    "forgot_sub": "Укажите почту, на которую заведён аккаунт. Пришлём ссылку — "
                  "по ней зададите новый пароль.",
    "forgot_btn": "Прислать ссылку",
    "forgot_back": "Вспомнили пароль? Войти",
    "forgot_sent_h": "Письмо отправлено",
    "forgot_sent_sub": "Если такой адрес у нас есть, письмо со ссылкой уже пришло на "
                       "{email}. Ссылка работает один раз и живёт час.",
    "forgot_sent_spam": "Не пришло за пару минут — загляните в «Спам» или",
    "forgot_sent_other": "попробуйте другой адрес",
    "forgot_to_login": "Вернуться ко входу",
    "reset_h": "Новый пароль",
    "reset_sub": "Придумайте пароль не короче восьми знаков. Им вы будете входить "
                 "и в приложение, и в кабинет.",
    "reset_broken": "Ссылка неполная — откройте её из письма целиком.",
    "reset_ask_new": "Запросить новую ссылку",
    "reset_btn": "Сохранить и войти",
    "reset_note": "После смены пароля все входы на других устройствах оборвутся — "
                  "войдите заново уже с новым.",

    # --- заголовки страниц ---
    "title_index": "Tunnelo — VPN, который не нужно выключать",
    "title_cabinet": "Личный кабинет — Tunnelo",
    "title_forgot": "Забыли пароль — Tunnelo",
    "title_reset": "Новый пароль — Tunnelo",
    "meta_description": "Умная маршрутизация трафика: зарубежные сервисы идут через "
                        "туннель, российские — напрямую. Банки, Госуслуги и Ozon "
                        "работают как обычно.",

    # --- ошибки ---
    "err_service": "Сервис недоступен. Попробуйте через минуту.",
    "err_credentials": "Логин или пароль не подошли",
    "err_code": "Код не подошёл",
    "err_send_code": "Не удалось отправить код",
    "err_send_link": "Не удалось отправить письмо",
    "err_reset": "Не удалось сменить пароль",
    "err_pw_mismatch": "Пароли не совпали — введите одинаковые.",
}

EN = {
    "nav_plans": "Pricing",
    "nav_contacts": "Contacts",
    "nav_cabinet": "Account",
    "cabinet_title": "Your account",
    "doc_offer": "Public offer",
    "doc_terms": "Terms and refunds",
    "doc_privacy": "Data processing",
    "doc_contacts": "Contacts",
    "docs_ru_note": "Legal documents are in Russian.",
    "foot_about": "Smart traffic routing service.",
    "foot_support": "Support",
    "foot_docs": "Documents",
    "foot_doc_offer": "Public offer",
    "foot_doc_terms": "Refunds and cancellation",
    "foot_doc_privacy": "Personal data",
    "foot_doc_contacts": "Company details",
    "foot_pay": "Payment",
    "foot_pay_note": "Payments are handled by a certified payment provider. "
                     "Your card details never reach us.",
    "foot_rights": "All rights reserved.",

    "hero_badge": "Smart routing: every site takes its own road",
    "hero_title_1": "Foreign services",
    "hero_title_2": "and Russian ones — together",
    "hero_p1": "An ordinary VPN pushes all your traffic through itself — and then your "
               "bank starts asking for confirmations, the marketplace shows someone "
               "else's prices, government sites misbehave. So you switch it on and off "
               "ten times a day.",
    "hero_p2_b": "Tunnelo splits the traffic itself.",
    "hero_p2": "Foreign services go through the tunnel, Russian ones go direct. "
               "At the same time, with nothing to switch.",
    "hero_cta_plans": "Choose a plan",
    "hero_cta_how": "How it works",
    "hero_note": "Your bank, government services and marketplaces work as usual. "
                 "YouTube and Telegram work as if there were no borders. At once.",
    "hero_fox_alt": "The Tunnelo fox with a lantern — light at the end of the tunnel",

    "how_title": "How it works",
    "how_sub": "An ordinary VPN drives everything through itself — banks start asking "
               "for confirmations and marketplaces show the wrong prices. "
               "Tunnelo splits the traffic.",
    "flow_device": "Your device",
    "flow_brand_1": "Tunnelo looks at",
    "flow_brand_2": "where you are going",
    "flow_direct_tag": "Russian sites — direct",
    "flow_direct_why": "The site sees your usual address. The bank asks for nothing "
                       "extra, the marketplace shows your prices, government services "
                       "let you in.",
    "flow_tunnel_tag": "Foreign services — through the tunnel",
    "flow_tunnel_why": "They open from a foreign address and the connection holds. "
                       "Nothing to switch — both roads work at the same time.",

    "cmp_bad_h": "An ordinary VPN",
    "cmp_good_h": "Tunnelo",
    "cmp_youtube": "YouTube works",
    "cmp_bank_bad": "the bank asks for confirmations",
    "cmp_bank_good": "the bank works",
    "cmp_shop_bad": "Ozon shows the wrong prices",
    "cmp_shop_good": "Ozon shows your prices",
    "cmp_gov_bad": "government services refuse",
    "cmp_gov_good": "government services let you in",
    "cmp_bad_f": "and so it goes, on and off, every time",
    "cmp_good_f": "switch it on once and forget",

    "dev_title": "One subscription — every device",
    "dev_text": "Phone, computer and tablet. The app is the same everywhere: "
                "install it, press one button, it works.",

    "card1_h": "Nothing to set up",
    "card1_p": "No keys, no picking servers. Install it, sign in, press the button — "
               "everything is ready.",
    "card2_h": "Banks and government sites stay calm",
    "card2_p": "Russian services see your usual address. You get in the first time, "
               "without endless confirmations.",
    "card3_h": "Speed, not just a connection",
    "card3_p": "A modern protocol over UDP keeps the speed high: video plays in real "
               "quality, not three hundred pixels with pauses.",

    "plan_dev_1": "1 device",
    "plan_dev_2": "2 devices",
    "plans_title": "Pricing",
    "plans_sub": "Pay for a year and it costs a third less",
    "plans_per_month": "₽ / month",
    "plans_or_year": "or {year} ₽ per year — that is {per} ₽ a month",
    "plans_or_year_short": "or {year} ₽ per year",
    "plans_btn_year": "For a year",
    "plans_btn_month": "For a month",

    "cab_login_h": "Sign in",
    "cab_login_sub": "Your login and password arrive by email — after payment or after "
                     "your first sign-in by email. The subscription lives on the "
                     "account: change your phone, sign in, carry on.",
    "cab_login_ph": "Login or email",
    "cab_pass_ph": "Password",
    "cab_enter": "Sign in",
    "cab_forgot_link": "Forgot your password?",
    "cab_forgot_tail": "We will send a link by email.",
    "cab_or": "or",
    "cab_bymail_note": "First time here, or no password yet — sign in by email. "
                       "We will send a code and set up your login and password.",
    "cab_bymail_btn": "Send a code by email",
    "cab_code_sent": "We sent a code to {email}. It is valid for 15 minutes.",
    "cab_code_ph": "000000",
    "cab_code_spam": "No email? Check the spam folder or",
    "cab_code_other": "try another address",
    "cab_sub_h": "Your subscription",
    "cab_exit": "sign out",
    "cab_state": "Status",
    "cab_state_on": "active",
    "cab_state_off": "expired",
    "cab_left": "Days left",
    "cab_days": "days",
    "cab_devices": "Devices",
    "cab_of": "of",
    "cab_ref_code": "Invite code",
    "cab_invited": "Invited",
    "cab_bonus": "granted",
    "cab_key_h": "Transfer code",
    "cab_key_note": "Enter it in the app on your second device — open «Promo code» "
                    "and paste it.",
    "cab_extend": "Extend",
    "cab_payments": "Payments",
    "cab_paid_msg": "Paid. The days will appear within a minute — refresh the page.",
    "cab_creds_h": "Your login and password",
    "cab_creds_note": "You sign in to the app and here with this pair. We also sent it "
                      "by email — but save it now, just in case.",
    "cab_pw_h": "Password",
    "cab_pw_current": "Current password",
    "cab_pw_new": "New password",
    "cab_pw_again": "Once more",
    "cab_pw_btn": "Change password",
    "cab_pw_ok": "Password changed. Other sessions were signed out.",
    "cab_pw_mismatch": "The passwords do not match — type the same one twice.",
    "cab_pw_fail": "The current password did not match.",

    "forgot_h": "Forgot your password",
    "forgot_sub": "Enter the email the account is registered to. We will send a link — "
                  "you set a new password there.",
    "forgot_btn": "Send the link",
    "forgot_back": "Remembered it? Sign in",
    "forgot_sent_h": "Email sent",
    "forgot_sent_sub": "If we have that address, the email with the link has already "
                       "arrived at {email}. The link works once and lives for an hour.",
    "forgot_sent_spam": "Nothing in a couple of minutes — check the spam folder or",
    "forgot_sent_other": "try another address",
    "forgot_to_login": "Back to sign-in",
    "reset_h": "New password",
    "reset_sub": "Pick a password of at least eight characters. You will use it both "
                 "in the app and here.",
    "reset_broken": "The link is incomplete — open it from the email in full.",
    "reset_ask_new": "Request a new link",
    "reset_btn": "Save and sign in",
    "reset_note": "After the change, sessions on other devices are signed out — "
                  "sign in again with the new password.",

    "title_index": "Tunnelo — the VPN you never have to switch off",
    "title_cabinet": "Your account — Tunnelo",
    "title_forgot": "Forgot your password — Tunnelo",
    "title_reset": "New password — Tunnelo",
    "meta_description": "Smart traffic routing: foreign services go through the tunnel, "
                        "Russian ones go direct. Banks, government services and Ozon "
                        "work as usual.",

    "err_service": "The service is unavailable. Try again in a minute.",
    "err_credentials": "Login or password did not match",
    "err_code": "The code did not match",
    "err_send_code": "Could not send the code",
    "err_send_link": "Could not send the email",
    "err_reset": "Could not change the password",
    "err_pw_mismatch": "The passwords do not match — type the same one twice.",
}

STRINGS = {"ru": RU, "en": EN}

# Остальные языки лежат по файлу на язык в lang/: так их правит и добавляет
# кто угодно, не трогая этот файл и не мешая друг другу.
_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lang")
for _code in CODES:
    if _code in STRINGS:
        continue
    _path = os.path.join(_DIR, f"{_code}.py")
    if not os.path.exists(_path):
        continue
    _ns = {}
    with open(_path, encoding="utf-8") as _fh:
        exec(compile(_fh.read(), _path, "exec"), _ns)  # noqa: S102
    if isinstance(_ns.get("STRINGS"), dict):
        STRINGS[_code] = _ns["STRINGS"]


def strings(lang):
    """Словарь строк для языка. Чего нет — берётся из русского."""
    if lang == DEFAULT or lang not in STRINGS:
        return dict(RU)
    out = dict(RU)
    out.update(STRINGS[lang])
    return out


def pick(query_lang, cookie_lang, accept_language):
    """Какой язык показать: выбор в адресе, потом печенье, потом браузер."""
    for candidate in (query_lang, cookie_lang):
        if candidate in CODES:
            return candidate
    for chunk in (accept_language or "").split(","):
        code = chunk.split(";")[0].strip().lower().split("-")[0]
        if code in CODES:
            return code
    return DEFAULT
