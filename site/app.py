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
from datetime import datetime, timezone

import httpx
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
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
               "при оплате за год — 1794 ₽ и 2994 ₽ соответственно")

# Цены: помесячно и за год со скидкой 50%.
PLANS = {
    "1d-1m":  {"id": "1d-1m",  "devices": 1, "term": "месяц", "price": 299,  "days": 30},
    "1d-12m": {"id": "1d-12m", "devices": 1, "term": "год",   "price": 1794, "days": 365},
    "2d-1m":  {"id": "2d-1m",  "devices": 2, "term": "месяц", "price": 499,  "days": 30},
    "2d-12m": {"id": "2d-12m", "devices": 2, "term": "год",   "price": 2994, "days": 365},
}

# Витрина: два тарифа, у каждого цена за месяц и за год.
PLAN_CARDS = [
    {
        "devices": "1 устройство",
        "month": {"id": "1d-1m", "price": 299},
        "year": {"id": "1d-12m", "price": 1794, "per_month": 150},
        "best": False,
    },
    {
        "devices": "2 устройства",
        "month": {"id": "2d-1m", "price": 499},
        "year": {"id": "2d-12m", "price": 2994, "per_month": 250},
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



def _ctx(request: Request, **extra):
    """Реквизиты и контакты нужны на каждой странице — собираем в одном месте."""
    base = {
        "request": request,
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
    return templates.TemplateResponse("index.html", _ctx(
        request, plans=PLAN_CARDS, trial_days=TRIAL_DAYS, devices=DEVICE_LIMIT,
    ))


@app.get("/cabinet", response_class=HTMLResponse)
async def cabinet(request: Request, paid: str = ""):
    """
    Личный кабинет. Вход по коду из письма — пароля нет намеренно:
    его забывают и крадут, а восстанавливать пришлось бы через ту же почту.
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
            request, error="Сервис недоступен. Попробуйте через минуту.",
            plans=PLAN_CARDS))
    if r.status_code != 200:
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, error=data.get("message") or "Не удалось отправить код",
            email=email, plans=PLAN_CARDS))
    return templates.TemplateResponse("cabinet.html", _ctx(
        request, email=email, code_sent=True, plans=PLAN_CARDS))


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
            request, error="Сервис недоступен. Попробуйте через минуту.",
            email=email, code_sent=True, plans=PLAN_CARDS))
    if r.status_code != 200 or not data.get("token"):
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, error=data.get("message") or "Код не подошёл",
            email=email, code_sent=True, plans=PLAN_CARDS))

    resp = RedirectResponse("/cabinet", status_code=303)
    # Печенье живёт год, только по HTTPS и недоступно скриптам:
    # это ключ от подписки, красть его нельзя.
    resp.set_cookie("tunnelo_session", data["token"], max_age=31536000,
                    httponly=True, secure=True, samesite="lax")
    return resp


@app.get("/cabinet/exit")
async def cabinet_exit():
    resp = RedirectResponse("/cabinet", status_code=303)
    resp.delete_cookie("tunnelo_session")
    return resp


@app.get("/pay")
async def pay(plan: str = "2d-12m", key: str = "", app: str = "", method: int = 11):
    """
    Создаёт платёж в Platega и уводит человека на страницу оплаты.

    Ключ подписки кладём в payload — он вернётся в уведомлении об оплате,
    и по нему мы поймём, кому продлевать. Способ по умолчанию — карта (11),
    СБП это 2, SberPay 14.
    """
    p = PLANS.get(plan) or PLANS["2d-12m"]

    if not (PLATEGA_MERCHANT and PLATEGA_SECRET):
        return RedirectResponse("/cabinet?pay=soon", status_code=303)

    order_id = f"{plan}-{key or 'new'}-{int(datetime.now(timezone.utc).timestamp())}"
    body = {
        "paymentMethod": method,
        "paymentDetails": {"amount": p["price"], "currency": "RUB"},
        "description": f"Tunnelo — {p['devices']} устр., {p['term']}",
        # Из приложения возвращаем в приложение, из браузера — в кабинет.
        "return": (f"{SITE_URL}/paid?key={key}" if app
                   else f"{SITE_URL}/cabinet?paid=1"),
        "failedUrl": f"{SITE_URL}/cabinet?pay=fail",
        "orderId": order_id,
        # payload вернётся в уведомлении дословно — кладём туда всё, что нужно
        # для продления: кому, на сколько и сколько устройств.
        "payload": json.dumps({"key": key, "days": p["days"],
                               "devices": p["devices"], "plan": plan},
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
            LOG.info("платёж создан: %s", data.get("transactionId"))
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
        LOG.warning("уведомление с чужими ключами отброшено")
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


@app.post("/register", response_class=HTMLResponse)
async def register(request: Request, email: str = Form(""), agree: str = Form("")):
    """
    Регистрация: почта — и сразу ключ. Пароля нет намеренно: он ничего
    не защищает в нашем случае и только отпугивает.
    """
    email = email.strip().lower()
    if not email or "@" not in email or not agree:
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, reg_error="Укажите почту и подтвердите согласие с условиями."))

    # Идентификатор устройства выводим из почты: повторная регистрация
    # с той же почтой вернёт тот же ключ, а не заведёт второй.
    device = "web-" + hashlib.sha256(email.encode()).hexdigest()[:24]
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.post(f"{ACTIVATION_URL}/activate",
                                  json={"code": "PARDAUTO", "device": device})
        data = r.json() if r.status_code < 500 else {}
        key = data.get("key")
    except Exception:
        key = None

    if not key:
        return templates.TemplateResponse("cabinet.html", _ctx(
            request, reg_error="Не удалось создать доступ. Напишите в поддержку, поможем."))

    return templates.TemplateResponse("cabinet.html", _ctx(
        request, new_key=key, key=key))


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


@app.get("/health")
async def health():
    return {"ok": True}
