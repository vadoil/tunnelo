"""
Сайт Tunnelo: скачивание приложений, тарифы, личный кабинет и оплата.

Держится на том же сервисе активации, что и приложение (api.amnez.online):
он знает про ключи, сроки и трафик. Сайт ничего не хранит у себя — он
спрашивает сервис и показывает ответ человеку.

Секреты платёжной системы читаются из переменных окружения и никогда
не попадают в страницы: подпись уведомления об оплате проверяется здесь.
"""

import asyncio
import hashlib
import hmac
import smtplib
from email.message import EmailMessage
import json
import logging
import os
import re
import time
from datetime import datetime, timezone

import httpx
from fastapi import FastAPI, Form, Request

import i18n
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
# Без basicConfig корневой логгер остаётся на WARNING без обработчиков, и
# записи о платежах («платёж создан», «продлено») терялись молча.
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
LOG = logging.getLogger("tunnelo")

# Сервис активации — единственный источник правды о подписках.
ACTIVATION_URL = os.getenv("TUNNELO_ACTIVATION_URL", "https://api.amnez.online")
# Секрет для /extend. Метод раздаёт оплаченные дни, сервис активации без
# секрета его не пускает — и правильно делает.
EXTEND_SECRET = os.getenv("TUNNELO_EXTEND_SECRET", "")
# Письма отправляем отсюда: у сервера с базой хостер закрыл исходящие SMTP.
# Пока внешний ящик не заведён, письмо уходит через локальный postfix —
# доходит, но в mail.ru и yandex часто попадает в спам. Настроенный SMTP
# с SPF и DKIM это лечит.
MAIL_SECRET = os.getenv("TUNNELO_MAIL_SECRET", "")
SMTP_HOST = os.getenv("TUNNELO_SMTP_HOST", "")
SMTP_PORT = int(os.getenv("TUNNELO_SMTP_PORT", "465"))
SMTP_USER = os.getenv("TUNNELO_SMTP_USER", "")
SMTP_PASS = os.getenv("TUNNELO_SMTP_PASS", "")
MAIL_FROM = os.getenv("TUNNELO_MAIL_FROM", "Tunnelo <noreply@tunello.online>")

# Enot: идентификатор магазина и секреты. Живут только в окружении сервера.
PLATEGA_MERCHANT = os.getenv("PLATEGA_MERCHANT", "")
PLATEGA_SECRET = os.getenv("PLATEGA_SECRET", "")
# Второй ключ Platega не нужен: подлинность уведомления она
# подтверждает теми же X-MerchantId и X-Secret.
PLATEGA_API = "https://app.platega.io/transaction/process"

SITE_URL = os.getenv("TUNNELO_SITE_URL", "https://tunello.online")
TRIAL_DAYS = int(os.getenv("TUNNELO_TRIAL_DAYS", "30"))
DEVICE_LIMIT = int(os.getenv("TUNNELO_DEVICE_LIMIT", "3"))


# Реквизиты продавца. Платёжная система требует, чтобы они были
# на сайте в открытом доступе, поэтому держим в одном месте
# и подставляем во все страницы и документы.
ORG = {
    "name": 'ООО «ТРИ И»',
    "inn": "0100014751",
    "kpp": "010001001",
    "ogrn": "1260100000544",
    "address": "385130, Россия, Республика Адыгея, Тахтамукайский район, "
               "пгт Энем, ул. Октябрьская, д. 16",
    "account": "40702810720000303167",
    "bank": 'ООО «Банк Точка»',
    "bik": "044525104",
    "corr": "30101810745374525104",
}
SUPPORT_PHONE = "+79033017383"

# Реквизиты юрлица на время согласования кассы скрыты — так просит платёжная
# система. После регистрации вернуть: TUNNELO_SHOW_ORG=1 в .env и перезапуск.
# Держать их скрытыми постоянно нельзя: публичная оферта без реквизитов
# исполнителя юридически слаба, покупателю не с кем судиться.
SHOW_ORG = os.getenv("TUNNELO_SHOW_ORG", "0") == "1"

# Кодовое слово для проверки платёжной системой. Убрать после регистрации.
REVIEW_CODE = os.getenv("TUNNELO_REVIEW_CODE", "плаtega")
SUPPORT_PHONE_PRETTY = "+7 903 301-73-83"
SUPPORT_EMAIL = os.getenv("TUNNELO_EMAIL", "support@tunello.online")
OFFER_DATE = "1 сентября 2026 года"
PRICES_TEXT = ("299 ₽ в месяц за одно устройство, 499 ₽ в месяц за два; "
               "при оплате за год — 2388 ₽ и 3996 ₽ соответственно")

# Цены: помесячно и за год на треть дешевле (199 и 333 ₽ в месяц).
PLANS = {
    "1d-1m":  {"id": "1d-1m",  "devices": 1, "term": "месяц", "price": 299,  "days": 30},
    "1d-12m": {"id": "1d-12m", "devices": 1, "term": "год",   "price": 2388, "days": 365},
    "2d-1m":  {"id": "2d-1m",  "devices": 2, "term": "месяц", "price": 499,  "days": 30},
    "2d-12m": {"id": "2d-12m", "devices": 2, "term": "год",   "price": 3996, "days": 365},
}

# Скидочные коды. Лежат файлом рядом с сайтом, а не в коде: добавить код или
# закрыть его нужно без выката и рестарта. Формат:
#   {"TEST90": {"off": 90, "until": "2026-12-31", "note": "проверка оплаты"}}
# off — процент скидки (1..99), until — последний день, когда код работает
# (необязательно). Дни подписки код не меняет: он только про цену.
COUPONS_PATH = os.getenv("TUNNELO_COUPONS", os.path.join(BASE_DIR, "coupons.json"))
_COUPONS = {"mtime": -1.0, "data": {}}


def coupon_get(code):
    """Скидка по коду или None. Файл перечитываем, когда он изменился."""
    code = (code or "").strip().upper()
    if not code:
        return None
    try:
        mtime = os.path.getmtime(COUPONS_PATH)
    except OSError:
        return None
    if mtime != _COUPONS["mtime"]:
        try:
            with open(COUPONS_PATH, encoding="utf-8") as fh:
                _COUPONS["data"] = {str(k).upper(): v for k, v in json.load(fh).items()}
            _COUPONS["mtime"] = mtime
        except Exception as e:
            # Битый файл не должен ронять оплату: продаём по полной цене.
            LOG.warning("файл скидок не прочитан: %s", e)
            return None
    c = _COUPONS["data"].get(code)
    if not isinstance(c, dict):
        return None
    try:
        off = int(c.get("off", 0))
    except (TypeError, ValueError):
        return None
    if not 1 <= off <= 99:
        return None
    until = str(c.get("until") or "")
    if until and until < datetime.now(timezone.utc).strftime("%Y-%m-%d"):
        return None
    return {"off": off, "note": str(c.get("note") or "")}


def apply_coupon(price, code):
    """Цена со скидкой и код, который сработал. Округляем до рубля вверх:
    платёжная система не любит копейки, а округление вниз дарит копейку."""
    c = coupon_get(code)
    if not c:
        return price, None
    return max(1, -(-price * (100 - c["off"]) // 100)), (code or "").strip().upper()

# Витрина: два тарифа, у каждого цена за месяц и за год.
PLAN_CARDS = [
    {
        "devices_key": "plan_dev_1",
        "month": {"id": "1d-1m", "price": 299},
        "year": {"id": "1d-12m", "price": 2388, "per_month": 199},
        "best": False,
    },
    {
        "devices_key": "plan_dev_2",
        "month": {"id": "2d-1m", "price": 499},
        "year": {"id": "2d-12m", "price": 3996, "per_month": 333},
        "best": True,
    },
]

app = FastAPI(title="Tunnelo", docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=os.path.join(BASE_DIR, "static")), name="static")
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))


def _plural_days(n: int) -> str:
    m10, m100 = n % 10, n % 100
    if m10 == 1 and m100 != 11:
        return "день"
    if 2 <= m10 <= 4 and not 12 <= m100 <= 14:
        return "дня"
    return "дней"


def _gb(b: int) -> str:
    return f"{b / 1024 ** 3:.1f} ГБ"



def _lang(request: Request):
    """Язык страницы: выбор в адресе, потом печенье, потом язык браузера."""
    return i18n.pick(request.query_params.get("lang", ""),
                     request.cookies.get(i18n.COOKIE, ""),
                     request.headers.get("accept-language", ""))


# Свежие сборки. Ссылки и номер версии берём из того же latest.json, по
# которому приложение проверяет обновления: одна правда на сайт и на клиент,
# и после выкладки новой версии сайт меняется сам.
RELEASES_URL = os.getenv("TUNNELO_RELEASES_URL", "https://api.amnez.online/dl/latest.json")
# Сами файлы лежат и здесь, рядом с сайтом: качать с tunello.online привычнее,
# чем с технического адреса api.amnez.online, да и живёт он отдельно. Чего нет
# на месте — остаётся по прежней ссылке, чтобы раздел не терял платформы.
DOWNLOADS_DIR = os.getenv("TUNNELO_DOWNLOADS", os.path.join(BASE_DIR, "downloads"))
_releases = {"at": 0.0, "data": {}}


def _local_link(url):
    """Ссылка на файл у нас, если он здесь есть. Иначе — как было."""
    name = url.rsplit("/", 1)[-1]
    if name and os.path.exists(os.path.join(DOWNLOADS_DIR, name)):
        return f"{SITE_URL}/downloads/{name}"
    return url


def latest_release():
    """Версия и ссылки на сборки. Недоступен сервер — отдаём, что помним."""
    now = time.monotonic()
    if _releases["data"] and now - _releases["at"] < 600:
        return _releases["data"]
    try:
        with httpx.Client(timeout=8) as client:
            data = client.get(RELEASES_URL).json()
        if isinstance(data, dict) and data.get("downloads"):
            _releases["data"] = {
                "version": str(data.get("version") or ""),
                "downloads": {k: _local_link(v) for k, v in data["downloads"].items()},
            }
            _releases["at"] = now
    except Exception as e:
        LOG.warning("список сборок не обновился: %s", e)
    return _releases["data"]


def _ctx(request: Request, **extra):
    """Реквизиты, контакты и строки языка нужны на каждой странице."""
    lang = _lang(request)
    base = {
        "request": request,
        "lang": lang,
        "langs": i18n.LANGS,
        "t": i18n.strings(lang),
        "org": ORG,
        "show_org": SHOW_ORG,
        "review_code": REVIEW_CODE,
        "phone": SUPPORT_PHONE,
        "phone_pretty": SUPPORT_PHONE_PRETTY,
        "email": SUPPORT_EMAIL,
        "offer_date": OFFER_DATE,
        "prices": PRICES_TEXT,
        "year": datetime.now(timezone.utc).year,
    }
    base.update(extra)
    return base


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    resp = templates.TemplateResponse("index.html", _ctx(
        request, plans=PLAN_CARDS, trial_days=TRIAL_DAYS, devices=DEVICE_LIMIT,
        release=latest_release(),
    ))
    return _remember_lang(request, resp)


def _remember_lang(request: Request, resp):
    """Язык, выбранный в адресе, запоминаем на год — чтобы не выбирать снова."""
    chosen = request.query_params.get("lang", "")
    if chosen in i18n.CODES:
        resp.set_cookie(i18n.COOKIE, chosen, max_age=31536000, samesite="lax")
    return resp


def _set_session(resp, token):
    """Печенье живёт год, только по HTTPS и недоступно скриптам:
    это ключ от подписки, красть его нельзя."""
    resp.set_cookie("tunnelo_session", token, max_age=31536000,
                    httponly=True, secure=True, samesite="lax")
    return resp


async def _activation(method, path, **kw):
    """Один поход в сервис аккаунтов. -> (код, тело) или (0, {}) если молчит."""
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.request(method, f"{ACTIVATION_URL}{path}", **kw)
        return r.status_code, r.json()
    except Exception:
        LOG.warning("сервис аккаунтов не ответил: %s %s", method, path)
        return 0, {}


@app.get("/cabinet", response_class=HTMLResponse)
async def cabinet(request: Request, paid: str = ""):
    """
    Личный кабинет. Вход — логин и пароль; пару человек получает письмом
    при оплате или при первом входе по почте. Пароль забыт — присылаем
    ссылку на смену (16.09.2026; до этого вход был только кодом из письма).
    """
    token = request.cookies.get("tunnelo_session", "")
    account = None
    if token:
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                r = await client.get(f"{ACTIVATION_URL}/me",
                                     headers={"Authorization": "Bearer " + token})
            if r.status_code == 200:
                account = r.json()
        except Exception:
            LOG.warning("кабинет: сервис аккаунтов не ответил")

    resp = templates.TemplateResponse("cabinet.html", _ctx(
        request, account=account, paid=bool(paid), plans=PLAN_CARDS))
    if token and account is None:
        # Сессия протухла — не держим мёртвую печенье.
        resp.delete_cookie("tunnelo_session")
    return resp


@app.post("/cabinet/code", response_class=HTMLResponse)
async def cabinet_code(request: Request, email: str = Form("")):
    """Выслать код на почту."""
    email = email.strip().lower()
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.post(f"{ACTIVATION_URL}/auth/request",
                                  json={"email": email})
        data = r.json()
    except Exception:
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, error=i18n.strings(_lang(request))["err_service"],
            plans=PLAN_CARDS))
    if r.status_code != 200:
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, error=data.get("message") or i18n.strings(_lang(request))["err_send_code"],
            email=email, plans=PLAN_CARDS))
    return templates.TemplateResponse("cabinet.html", _ctx(
        request, form_email=email, code_sent=True, plans=PLAN_CARDS))


@app.post("/cabinet/enter", response_class=HTMLResponse)
async def cabinet_enter(request: Request, email: str = Form(""), code: str = Form("")):
    """Обменять код на сессию."""
    email, code = email.strip().lower(), code.strip()
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.post(f"{ACTIVATION_URL}/auth/verify",
                                  json={"email": email, "code": code})
        data = r.json()
    except Exception:
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, error=i18n.strings(_lang(request))["err_service"],
            form_email=email, code_sent=True, plans=PLAN_CARDS))
    if r.status_code != 200 or not data.get("token"):
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, error=data.get("message") or i18n.strings(_lang(request))["err_code"],
            email=email, code_sent=True, plans=PLAN_CARDS))

    if data.get("newPassword"):
        # Первый вход: сервис только что завёл пару логин/пароль. Показываем её
        # один раз здесь — письмо с ней тоже ушло, но экран человек видит сразу.
        page = templates.TemplateResponse("cabinet.html", _ctx(
            request, account=data, plans=PLAN_CARDS,
            new_login=data["newLogin"], new_password=data["newPassword"]))
        return _set_session(page, data["token"])
    return _set_session(RedirectResponse("/cabinet", status_code=303), data["token"])


@app.post("/cabinet/login", response_class=HTMLResponse)
async def cabinet_login(request: Request, login: str = Form(""), password: str = Form("")):
    """Вход парой логин/пароль. Логином работает и адрес почты."""
    login = login.strip().lower()
    st, data = await _activation("POST", "/auth/login",
                                 json={"login": login, "password": password})
    if st == 0:
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, error=i18n.strings(_lang(request))["err_service"],
            login=login, plans=PLAN_CARDS))
    if st != 200 or not data.get("token"):
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, error=data.get("message") or i18n.strings(_lang(request))["err_credentials"],
            login=login, plans=PLAN_CARDS))
    return _set_session(RedirectResponse("/cabinet", status_code=303), data["token"])


@app.get("/cabinet/forgot", response_class=HTMLResponse)
async def cabinet_forgot_form(request: Request):
    return templates.TemplateResponse("forgot.html", _ctx(request))


@app.post("/cabinet/forgot", response_class=HTMLResponse)
async def cabinet_forgot(request: Request, email: str = Form("")):
    """Выслать ссылку на смену пароля. Ответ одинаковый для любого адреса."""
    email = email.strip().lower()
    st, data = await _activation("POST", "/auth/forgot", json={"email": email})
    if st == 0:
        return templates.TemplateResponse("forgot.html", _ctx(
            request, error=i18n.strings(_lang(request))["err_service"], form_email=email))
    if st != 200:
        return templates.TemplateResponse("forgot.html", _ctx(
            request, error=data.get("message") or i18n.strings(_lang(request))["err_send_link"],
            email=email))
    return templates.TemplateResponse("forgot.html", _ctx(request, sent=True, form_email=email))


@app.get("/cabinet/reset", response_class=HTMLResponse)
async def cabinet_reset_form(request: Request, token: str = ""):
    return templates.TemplateResponse("reset.html", _ctx(request, token=token.strip()))


@app.post("/cabinet/reset", response_class=HTMLResponse)
async def cabinet_reset(request: Request, token: str = Form(""),
                        password: str = Form(""), password2: str = Form("")):
    """Задать новый пароль по ссылке из письма."""
    token = token.strip()
    if password != password2:
        return templates.TemplateResponse("reset.html", _ctx(
            request, token=token, error=i18n.strings(_lang(request))["err_pw_mismatch"]))
    st, data = await _activation("POST", "/auth/reset",
                                 json={"token": token, "password": password})
    if st == 0:
        return templates.TemplateResponse("reset.html", _ctx(
            request, token=token, error=i18n.strings(_lang(request))["err_service"]))
    if st != 200 or not data.get("token"):
        return templates.TemplateResponse("reset.html", _ctx(
            request, token=token,
            error=data.get("message") or i18n.strings(_lang(request))["err_reset"]))
    # Пароль сменили — сразу впускаем, повторно логиниться незачем.
    return _set_session(RedirectResponse("/cabinet", status_code=303), data["token"])


@app.post("/cabinet/password", response_class=HTMLResponse)
async def cabinet_password(request: Request, current: str = Form(""),
                           password: str = Form(""), password2: str = Form("")):
    """Смена пароля из кабинета."""
    token = request.cookies.get("tunnelo_session", "")
    if not token:
        return RedirectResponse("/cabinet", status_code=303)
    if password != password2:
        return RedirectResponse("/cabinet?pw=mismatch", status_code=303)
    st, data = await _activation(
        "POST", "/auth/password",
        json={"current": current, "password": password},
        headers={"Authorization": "Bearer " + token})
    if st == 200:
        return RedirectResponse("/cabinet?pw=ok", status_code=303)
    return RedirectResponse("/cabinet?pw=fail", status_code=303)


@app.get("/cabinet/exit")
async def cabinet_exit():
    resp = RedirectResponse("/cabinet", status_code=303)
    resp.delete_cookie("tunnelo_session")
    return resp


@app.get("/pay")
async def pay(plan: str = "2d-12m", key: str = "", app: str = "", method: int = 11,
              promo: str = ""):
    """
    Создаёт платёж в Platega и уводит человека на страницу оплаты.

    Ключ подписки кладём в payload — он вернётся в уведомлении об оплате,
    и по нему мы поймём, кому продлевать. Способ по умолчанию — карта (11),
    СБП это 2, SberPay 14.

    `promo` — скидочный код из coupons.json. Он меняет только сумму: дни и
    число устройств остаются тарифными, иначе скидка молча урезала бы срок.
    """
    # Неизвестный тариф раньше молча становился самым дорогим, а ключ уходил в
    # orderId и return-URL как есть. Способы: 11 карта, 2 СБП, 14 SberPay.
    p = PLANS.get(plan)
    if p is None or method not in (2, 11, 14) or (key and not re.fullmatch(r"[a-z0-9]{8,64}", key)):
        return JSONResponse({"error": "bad request"}, status_code=400)

    if not (PLATEGA_MERCHANT and PLATEGA_SECRET):
        return RedirectResponse("/cabinet?pay=soon", status_code=303)

    price, used_promo = apply_coupon(p["price"], promo)
    order_id = f"{plan}-{key or 'new'}-{int(datetime.now(timezone.utc).timestamp())}"
    body = {
        "paymentMethod": method,
        "paymentDetails": {"amount": price, "currency": "RUB"},
        "description": (f"Tunnelo — {p['devices']} устр., {p['term']}"
                        + (f" (промокод {used_promo})" if used_promo else "")),
        # Из приложения возвращаем в приложение, из браузера — в кабинет.
        "return": (f"{SITE_URL}/paid?key={key}" if app
                   else f"{SITE_URL}/cabinet?paid=1"),
        "failedUrl": f"{SITE_URL}/cabinet?pay=fail",
        "orderId": order_id,
        # payload вернётся в уведомлении дословно — кладём туда всё, что нужно
        # для продления: кому, на сколько и сколько устройств.
        "payload": json.dumps({"key": key, "days": p["days"],
                               "devices": p["devices"], "plan": plan,
                               "promo": used_promo or ""},
                              ensure_ascii=False),
    }
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.post(
                PLATEGA_API, json=body,
                headers={"X-MerchantId": PLATEGA_MERCHANT,
                         "X-Secret": PLATEGA_SECRET,
                         "Content-Type": "application/json"})
        data = r.json()
        link = data.get("redirect")
        if link:
            LOG.info("платёж создан: %s на %s ₽%s", data.get("transactionId"), price,
                     f" по промокоду {used_promo} (−{p['price'] - price} ₽)" if used_promo else "")
            return RedirectResponse(link, status_code=303)
        LOG.warning("Platega не вернула ссылку: %s", str(data)[:300])
    except Exception as e:
        LOG.warning("Platega недоступна: %s", e)
    return RedirectResponse("/cabinet?pay=error", status_code=303)


@app.post("/api/pay/callback")
async def pay_callback(request: Request):
    """
    Уведомление об оплате от Platega.

    Подлинность проверяем по заголовкам X-MerchantId и X-Secret: система
    присылает в них те же значения, что мы используем сами. Без проверки
    любой желающий продлевал бы себе подписку простым запросом.

    Сравниваем побайтово через compare_digest, а не через ==, чтобы по
    времени ответа нельзя было подобрать ключ.
    """
    if not (PLATEGA_MERCHANT and PLATEGA_SECRET):
        LOG.warning("уведомление отброшено: касса не настроена")
        return JSONResponse({"error": "not configured"}, status_code=503)

    ok_merchant = hmac.compare_digest(
        request.headers.get("x-merchantid", ""), PLATEGA_MERCHANT)
    ok_secret = hmac.compare_digest(
        request.headers.get("x-secret", ""), PLATEGA_SECRET)
    if not (ok_merchant and ok_secret):
        # Чем именно не сошлось — видно только здесь. Самого секрета в журнал
        # не пишем: хватает длины и того, какие заголовки вообще пришли.
        got_secret = request.headers.get("x-secret", "")
        LOG.warning(
            "уведомление с чужими ключами отброшено: merchant %s, secret %s "
            "(пришло %d знаков, ждём %d), заголовки: %s",
            "совпал" if ok_merchant else f"не совпал ({request.headers.get('x-merchantid', '—')})",
            "совпал" if ok_secret else "не совпал",
            len(got_secret), len(PLATEGA_SECRET),
            ", ".join(sorted(request.headers.keys())),
        )
        return JSONResponse({"error": "forbidden"}, status_code=403)

    raw = await request.json()
    status = str(raw.get("status") or "")
    tx = raw.get("id")

    if status != "CONFIRMED":
        # CANCELED и CHARGEBACKED тоже приходят сюда. Продлевать нечего,
        # но записать нужно: возвраты придётся разбирать руками.
        LOG.info("платёж %s: статус %s", tx, status)
        return {"ok": True}

    fields = raw.get("payload") or {}
    if isinstance(fields, str):
        try:
            fields = json.loads(fields)
        except Exception:
            fields = {}

    key = (fields.get("key") or "").strip()
    days = int(fields.get("days") or 30)
    if not key:
        # Оплата без ключа: человек платил до регистрации. Разберём вручную —
        # номер платежа и сумма записаны в журнал.
        LOG.warning("оплата без ключа: платёж %s на %s", tx, raw.get("amount"))
        return {"ok": True}

    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.post(
                f"{ACTIVATION_URL}/extend",
                json={"key": key, "days": days,
                      "devices": int(fields.get("devices") or 1),
                      "order_id": str(tx), "amount": raw.get("amount"),
                      "plan": fields.get("plan")},
                headers={"X-Tunnelo-Secret": EXTEND_SECRET},
            )
        if r.status_code == 200:
            LOG.info("продлено %s на %s дней, платёж %s", key, days, tx)
        else:
            # Двухсотый ответ уже отправлен, повтора не будет. Пишем громко.
            LOG.error("ДЕНЬГИ ПОЛУЧЕНЫ, ПРОДЛЕНИЕ НЕ ПРОШЛО: ключ %s, дней %s, "
                      "платёж %s, сервис ответил %s %s",
                      key, days, tx, r.status_code, r.text[:200])
    except Exception as e:
        # Деньги получены — молчать нельзя, иначе продление потеряется.
        LOG.error("НЕ УДАЛОСЬ ПРОДЛИТЬ %s на %s дней (платёж %s): %s", key, days, tx, e)

    return {"ok": True}


@app.get("/offer", response_class=HTMLResponse)
async def offer(request: Request):
    return templates.TemplateResponse("offer.html", _ctx(request))


@app.get("/terms", response_class=HTMLResponse)
async def terms(request: Request):
    return templates.TemplateResponse("terms.html", _ctx(request))


@app.get("/privacy", response_class=HTMLResponse)
async def privacy(request: Request):
    return templates.TemplateResponse("privacy.html", _ctx(request))


@app.get("/contacts", response_class=HTMLResponse)
async def contacts(request: Request):
    return templates.TemplateResponse("contacts.html", _ctx(request))


@app.post("/internal/mail")
async def internal_mail(request: Request):
    """
    Отправка письма по просьбе сервиса активации (коды входа, чеки).

    Сервис активации живёт у хостера, который закрыл исходящие SMTP, поэтому
    письма уходят отсюда: локальный postfix пересылает их через Resend, где
    tunello.online подтверждён (SPF и DKIM на месте). Наружу метод открыт,
    поэтому закрыт секретом: иначе с нашего адреса сможет писать кто угодно,
    и домен быстро окажется в чёрных списках.

    Маршрут уже терялся однажды при переписывании оплаты — и коды входа
    молча перестали приходить (сервис получал 404). Не удалять.
    """
    if not MAIL_SECRET:
        return JSONResponse({"error": "mail not configured"}, status_code=503)
    if not hmac.compare_digest(request.headers.get("x-tunnelo-secret", ""), MAIL_SECRET):
        return JSONResponse({"error": "forbidden"}, status_code=403)

    body = await request.json()
    to = str(body.get("to", "")).strip()
    subject = str(body.get("subject", "")).strip() or "Tunnelo"
    text = str(body.get("text", ""))
    if "@" not in to or not text:
        return JSONResponse({"error": "bad request"}, status_code=400)

    msg = EmailMessage()
    msg["From"] = MAIL_FROM
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(text)

    def send():
        if SMTP_HOST:
            if SMTP_PORT == 465:
                with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=20) as srv:
                    if SMTP_USER:
                        srv.login(SMTP_USER, SMTP_PASS)
                    srv.send_message(msg)
            else:
                with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as srv:
                    srv.starttls()
                    if SMTP_USER:
                        srv.login(SMTP_USER, SMTP_PASS)
                    srv.send_message(msg)
        else:
            with smtplib.SMTP("127.0.0.1", 25, timeout=20) as srv:
                srv.send_message(msg)

    try:
        await asyncio.to_thread(send)
    except Exception as e:
        LOG.error("письмо на %s не ушло: %s", to, e)
        return JSONResponse({"error": "send failed"}, status_code=502)
    LOG.info("письмо отправлено на %s", to)
    return {"ok": True}


@app.get("/paid", response_class=HTMLResponse)
async def paid(key: str = ""):
    """
    Сюда Platega возвращает человека после оплаты из приложения. Открыть
    tunnelo://paid напрямую браузеры часто отказываются, поэтому страница с
    кнопкой: нажал — приложение открылось на экране подписки.
    """
    link = "tunnelo://paid" + (f"?key={key}" if re.fullmatch(r"[a-z0-9]{8,64}", key or "") else "")
    return HTMLResponse(
        "<!doctype html><html lang='ru'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>Tunnelo — оплата прошла</title>"
        "<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#0C1230;color:#EAF6F1;"
        "display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px;text-align:center}"
        "a{display:inline-block;margin-top:20px;padding:14px 26px;border-radius:14px;background:#5FE0B8;color:#0C1230;"
        "font-weight:600;text-decoration:none}</style></head><body><div>"
        "<h1>Оплата прошла</h1><p>Подписка продлится сама. Вернитесь в приложение.</p>"
        f"<a href='{link}'>Открыть Tunnelo</a>"
        "</div></body></html>"
    )


@app.get("/health")
async def health():
    return {"ok": True}
