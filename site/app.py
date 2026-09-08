"""
Сайт Tunnelo: скачивание приложений, тарифы, личный кабинет и оплата.

Держится на том же сервисе активации, что и приложение (api.amnez.online):
он знает про ключи, сроки и трафик. Сайт ничего не хранит у себя — он
спрашивает сервис и показывает ответ человеку.

Секреты платёжной системы читаются из переменных окружения и никогда
не попадают в страницы: подпись уведомления об оплате проверяется здесь.
"""

import hashlib
import hmac
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

# Enot: идентификатор магазина и секреты. Живут только в окружении сервера.
ENOT_SHOP_ID = os.getenv("ENOT_SHOP_ID", "")
ENOT_SECRET = os.getenv("ENOT_SECRET", "")
ENOT_SECRET_2 = os.getenv("ENOT_SECRET_2", "")
ENOT_API = "https://api.enot.io/invoice/create"

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
async def cabinet(request: Request, key: str = ""):
    key = key.strip()
    status = error = None

    if key:
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                r = await client.get(f"{ACTIVATION_URL}/status/{key}")
            if r.status_code == 200:
                data = r.json()
                days = int(data.get("daysLeft") or 0)
                used = int(data.get("up") or 0) + int(data.get("down") or 0)
                status = {
                    "active": bool(data.get("active")),
                    "days_text": f"{days} {_plural_days(days)}" if days else "истекла",
                    "traffic_text": _gb(used),
                }
            else:
                error = "Такой ключ не найден. Проверьте, не потерялся ли символ."
        except Exception:
            error = "Не удалось связаться с сервером. Попробуйте через минуту."

    return templates.TemplateResponse("cabinet.html", _ctx(
        request, key=key, status=status, error=error,
    ))


@app.get("/pay")
async def pay(plan: str = "2d-12m", key: str = "", app: str = ""):
    """
    Создаёт счёт в Enot и уводит человека на страницу оплаты.

    Ключ подписки кладём в custom_fields — он вернётся в уведомлении
    об оплате, и по нему мы поймём, кому продлевать.
    """
    p = PLANS.get(plan) or PLANS["2d-12m"]

    if not (ENOT_SHOP_ID and ENOT_SECRET):
        return RedirectResponse("/cabinet?pay=soon", status_code=303)

    order_id = f"{plan}-{key or 'new'}-{int(datetime.now(timezone.utc).timestamp())}"
    payload = {
        "amount": p["price"],
        "order_id": order_id,
        "shop_id": ENOT_SHOP_ID,
        "currency": "RUB",
        "comment": f"Tunnelo — {p['devices']} устр., {p['term']}",
        # custom_fields по документации — строка JSON, а не объект.
        "custom_fields": json.dumps({"key": key, "days": p["days"],
                                     "devices": p["devices"]}, ensure_ascii=False),
        "hook_url": f"{SITE_URL}/api/pay/callback",
        # Из приложения возвращаем в приложение, из браузера — в кабинет.
        "success_url": (f"{SITE_URL}/paid?key={key}" if app
                        else f"{SITE_URL}/cabinet?key={key}&paid=1"),
        "fail_url": f"{SITE_URL}/cabinet?pay=fail",
        "expire": 60,
    }
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.post(
                ENOT_API, json=payload,
                headers={"x-api-key": ENOT_SECRET,
                         "Accept": "application/json",
                         "Content-Type": "application/json"})
        data = r.json()
        link = (data.get("data") or data).get("url")
        if link:
            return RedirectResponse(link, status_code=303)
        LOG.warning("Enot не вернул ссылку: %s", str(data)[:300])
    except Exception as e:
        LOG.warning("Enot недоступен: %s", e)
    return RedirectResponse("/cabinet?pay=error", status_code=303)


@app.get("/paid", response_class=HTMLResponse)
async def paid(key: str = ""):
    """
    Возврат в приложение после оплаты.

    Открывается в браузере поверх Tunnelo. Сразу пробуем открыть приложение
    по своей схеме; если браузер это заблокировал — остаётся кнопка.
    Ссылка ведёт на tunnelo://paid, приложение по ней обновляет подписку.
    """
    deep = f"tunnelo://paid?key={key}"
    return HTMLResponse(
        "<!doctype html><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        "<title>Оплачено — Tunnelo</title>"
        "<style>body{font:16px/1.5 -apple-system,system-ui,sans-serif;"
        "background:#EDF7F2;color:#223B34;margin:0;display:grid;"
        "place-items:center;min-height:100vh;text-align:center;padding:24px}"
        "a{display:inline-block;margin-top:20px;background:#4E9C87;color:#fff;"
        "text-decoration:none;padding:14px 26px;border-radius:14px;"
        "font-weight:600}p{color:#5E7C72}</style>"
        "<div><h1>Оплачено</h1>"
        "<p>Возвращаемся в Tunnelo.<br>Если ничего не произошло — нажмите кнопку.</p>"
        f"<a href='{deep}'>Открыть Tunnelo</a></div>"
        f"<script>location.href={deep!r}</script>"
    )


@app.post("/api/pay/callback")
async def pay_callback(request: Request):
    """
    Уведомление об оплате от Enot.

    Подпись обязательна: без проверки любой желающий продлевал бы себе
    подписку простым запросом. Считается ровно как в документации —
    sha256 hmac от тела, отсортированного по ключам, дополнительным
    ключом кассы; приходит в заголовке x-api-sha256-signature.
    """
    raw = await request.json()
    got = request.headers.get("x-api-sha256-signature", "")

    if not ENOT_SECRET_2:
        LOG.warning("уведомление отброшено: дополнительный ключ не задан")
        return JSONResponse({"error": "not configured"}, status_code=503)

    body = json.dumps(raw, sort_keys=True, separators=(", ", ": "))
    want = hmac.new(ENOT_SECRET_2.encode(), body.encode("utf-8"),
                    hashlib.sha256).hexdigest()

    if not hmac.compare_digest(got, want):
        LOG.warning("уведомление с неверной подписью, заказ %s", raw.get("order_id"))
        return JSONResponse({"error": "bad signature"}, status_code=403)

    if str(raw.get("status")) not in ("success", "1"):
        return {"ok": True}

    fields = raw.get("custom_fields") or {}
    if isinstance(fields, str):
        try:
            fields = json.loads(fields)
        except Exception:
            fields = {}

    key = (fields.get("key") or "").strip()
    days = int(fields.get("days") or 30)
    if not key:
        # Оплата без ключа: человек платил до регистрации. Разберём вручную —
        # заказ и сумма записаны в журнал.
        LOG.warning("оплата без ключа, заказ %s на %s", raw.get("order_id"), raw.get("amount"))
        return {"ok": True}

    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.post(
                f"{ACTIVATION_URL}/extend",
                json={"key": key, "days": days,
                      "devices": int(fields.get("devices") or 1)},
                headers={"X-Tunnelo-Secret": EXTEND_SECRET},
            )
        if r.status_code == 200:
            LOG.info("продлено %s на %s дней", key, days)
        else:
            # Двухсотый ответ Enot уже отправлен, повтора не будет. Пишем громко.
            LOG.error("ДЕНЬГИ ПОЛУЧЕНЫ, ПРОДЛЕНИЕ НЕ ПРОШЛО: ключ %s, дней %s, "
                      "сервис ответил %s %s", key, days, r.status_code, r.text[:200])
    except Exception as e:
        # Деньги получены — молчать нельзя, иначе продление потеряется.
        LOG.error("НЕ УДАЛОСЬ ПРОДЛИТЬ %s на %s дней: %s", key, days, e)

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
