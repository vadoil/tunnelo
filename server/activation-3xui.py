#!/usr/bin/env python3
"""
Tunnelo Activation Service (3x-ui edition)
===========================================
Прослойка между приложением и панелью 3x-ui.

Токен панели живёт только здесь — в APK его быть не должно, достанут за пять минут.

Эндпоинты (для приложения):
  POST /activate      {"code":"PARDAUTO","device":"<hwid>"}
                      -> {"key","subscription","expires","daysLeft","reused"}
  GET  /status/<key>  -> {"active","daysLeft","expires","subscription"}
  GET  /sub/<key>     -> подписка ТОЛЬКО с Hysteria2 (см. ниже)
  GET  /health        -> {"ok":true,"inbounds":11}

Про подписку:
  Само содержимое подписки собирает sub-сервер 3x-ui. Приложение построено на
  sing-box: Reality из Xray 26.x он не поднимает (reality verification failed),
  XHTTP не понимает вовсе. При этом балансер в приложении строится по ВСЕМ
  серверам из подписки, включая нерабочие, и трафик уходит то в живой канал, то
  в мёртвый — снаружи это выглядит как «YouTube работает через раз».

  Поэтому /sub/<key> проксирует подписку 3x-ui и отдаёт только те строки, чей
  протокол приложение действительно умеет (SUB_PROTOCOLS, по умолчанию
  hysteria2). Фильтр стоит ИМЕННО НА ВЫДАЧЕ: привязка клиента к инбаундам не
  меняется. Это принципиально — смена привязки молча отцепляет клиента от
  инбаунда и требует bulkAttach, и заодно исходная ссылка панели
  (panel.amnez.online/sub/<key>) продолжает отдавать всё, включая Reality, для
  сторонних клиентов вроде Happ, где он работает.

  ?all=1 — отдать без фильтра, для отладки и тех же сторонних клиентов.

Логика:
  1. код есть в списке и не исчерпан?
  2. это устройство уже активировало код -> вернуть тот же ключ (не плодим клиентов)
  3. создать клиента с ОДНИМ subId сразу на ВСЕХ инбаундах -> одна подписка,
     в которой все страны и все протоколы
  4. вернуть ссылку подписки

Запуск:
  PANEL_URL='https://host:port/basePath' PANEL_TOKEN='...' \
  SUB_URI='https://host:2096/sub/' python3 activation-3xui.py
"""
import base64
import json
import os
import re
import secrets
import sqlite3
import string
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PANEL_URL = os.environ.get("PANEL_URL", "").rstrip("/")
PANEL_TOKEN = os.environ.get("PANEL_TOKEN", "")
SUB_URI = os.environ.get("SUB_URI", "").rstrip("/") + "/"
PORT = int(os.environ.get("PORT", "8099"))
DB = os.environ.get("DB_PATH", "/opt/tunnelo/activations.db")
# какие инбаунды выдавать: пусто = все, иначе список id через запятую
ONLY_INBOUNDS = [int(x) for x in os.environ.get("INBOUND_IDS", "").split(",") if x.strip()]
# сколько устройств на один ключ
LIMIT_IP = int(os.environ.get("LIMIT_IP", "3"))
# откуда брать саму подписку (sub-сервер 3x-ui, слушает локально)
SUB_UPSTREAM = os.environ.get("SUB_UPSTREAM", "http://127.0.0.1:2096").rstrip("/")
# какие протоколы отдавать приложению; пусто = без фильтра
SUB_PROTOCOLS = [x.strip().lower() for x in
                 os.environ.get("SUB_PROTOCOLS", "hysteria2,hy2").split(",") if x.strip()]

# Секрет для /extend. Метод раздаёт оплаченные дни, поэтому без секрета он
# выключен: иначе продлить себе подписку сможет кто угодно, кто найдёт адрес.
EXTEND_SECRET = os.environ.get("EXTEND_SECRET", "")
# Сколько дней получают обе стороны за приглашение друга.
REFERRAL_DAYS = int(os.environ.get("REFERRAL_DAYS", "15"))

# Письма отправляет сайт: у этого сервера хостер закрыл исходящие SMTP-порты
# (25, 465, 587), а HTTPS работает. Поэтому код входа мы генерируем здесь,
# а отправку просим сделать сайт — он в той же связке и SMTP оттуда открыт.
MAIL_URL = os.environ.get("MAIL_URL", "")
MAIL_SECRET = os.environ.get("MAIL_SECRET", "")
# Сколько живёт код входа и сколько раз можно ошибиться.
CODE_TTL = int(os.environ.get("CODE_TTL", "900"))
CODE_TRIES = int(os.environ.get("CODE_TRIES", "5"))
# Не чаще одного письма в минуту на адрес — иначе почтой можно завалить чужой ящик.
CODE_COOLDOWN = int(os.environ.get("CODE_COOLDOWN", "60"))

PROMO_CODES = {
    "PARDAUTO": {"days": 30, "limit": 0, "note": "первый месяц бесплатно"},
}

DEVICE_RE = re.compile(r"^[A-Za-z0-9_\-]{8,64}$")
CODE_RE = re.compile(r"^[A-Z0-9\-]{4,32}$")
KEY_RE = re.compile(r"^[a-z0-9]{16}$")
EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s.]+(\.[^@\s.]+)+$")
TOKEN_RE = re.compile(r"^[A-Za-z0-9_\-]{32,128}$")

for name, val in (("PANEL_URL", PANEL_URL), ("PANEL_TOKEN", PANEL_TOKEN), ("SUB_URI", SUB_URI)):
    if not val or val == "/":
        sys.exit(f"{name} не задан")


# ---------- база -------------------------------------------------------------
def db():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    c = sqlite3.connect(DB, timeout=10)
    c.execute("""CREATE TABLE IF NOT EXISTS activations(
        device TEXT NOT NULL,
        code   TEXT NOT NULL,
        sub_id TEXT NOT NULL,
        email  TEXT NOT NULL,
        created TEXT NOT NULL,
        PRIMARY KEY (device, code))""")
    c.execute("CREATE INDEX IF NOT EXISTS idx_code ON activations(code)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_sub ON activations(sub_id)")
    # Сколько устройств куплено на подписку. В панели limitIp одинаковый для
    # всех — коммерческий лимит считаем у себя, чтобы не трогать привязки:
    # смена привязки молча отцепляет клиента от инбаунда.
    c.execute("""CREATE TABLE IF NOT EXISTS subs(
        sub_id       TEXT PRIMARY KEY,
        device_limit INTEGER NOT NULL DEFAULT 1,
        updated      TEXT)""")
    # Кто чей код ввёл. Ввести можно один раз — отсюда PRIMARY KEY.
    c.execute("""CREATE TABLE IF NOT EXISTS referrals(
        referee_sub  TEXT PRIMARY KEY,
        referrer_sub TEXT NOT NULL,
        days         INTEGER NOT NULL,
        created      TEXT NOT NULL)""")
    c.execute("CREATE INDEX IF NOT EXISTS idx_ref ON referrals(referrer_sub)")
    # Учётные данные. Живут рядом с панелью намеренно: так состояние аккаунта
    # и состояние подписки в 3x-ui не могут разъехаться.
    c.execute("""CREATE TABLE IF NOT EXISTS users(
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        email   TEXT NOT NULL UNIQUE,
        created TEXT NOT NULL)""")
    # Одноразовые коды входа. Пароля нет намеренно: его забывают и крадут,
    # а восстановление всё равно шло бы через ту же почту.
    c.execute("""CREATE TABLE IF NOT EXISTS login_codes(
        email   TEXT PRIMARY KEY,
        code    TEXT NOT NULL,
        expires REAL NOT NULL,
        sent    REAL NOT NULL,
        tries   INTEGER NOT NULL DEFAULT 0)""")
    c.execute("""CREATE TABLE IF NOT EXISTS sessions(
        token   TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created TEXT NOT NULL,
        seen    TEXT)""")
    # Подписка у человека одна, поэтому связь один к одному.
    c.execute("""CREATE TABLE IF NOT EXISTS user_subs(
        user_id INTEGER PRIMARY KEY,
        sub_id  TEXT NOT NULL)""")
    c.execute("CREATE INDEX IF NOT EXISTS idx_usub ON user_subs(sub_id)")
    c.execute("""CREATE TABLE IF NOT EXISTS payments(
        order_id TEXT PRIMARY KEY,
        user_id  INTEGER,
        sub_id   TEXT,
        amount   REAL NOT NULL,
        plan     TEXT,
        days     INTEGER,
        devices  INTEGER,
        status   TEXT NOT NULL,
        created  TEXT NOT NULL)""")
    return c


# ---------- панель -----------------------------------------------------------
def panel(method, path, body=None, timeout=25):
    req = urllib.request.Request(
        PANEL_URL + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
    )
    req.add_header("Authorization", "Bearer " + PANEL_TOKEN)
    req.add_header("Content-Type", "application/json")
    import ssl
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        raw = r.read().decode()
    if not raw.strip():
        return {}
    d = json.loads(raw)
    if isinstance(d, dict) and d.get("success") is False:
        raise RuntimeError(f"panel: {d.get('msg')}")
    return d.get("obj", d)


def proto_alias(protocol):
    """Протокол инбаунда в панели -> схема ссылки в подписке.
    Панель зовёт Hysteria2 просто «hysteria», в ссылке же стоит hysteria2://."""
    p = (protocol or "").lower()
    return "hysteria2" if p in ("hysteria", "hysteria2") else p


def inbound_ids():
    """Все включённые инбаунды панели (или только заданные в INBOUND_IDS)."""
    lst = panel("GET", "/panel/api/inbounds/list")
    ids = [i["id"] for i in lst if i.get("enable", True)]
    if ONLY_INBOUNDS:
        ids = [i for i in ids if i in ONLY_INBOUNDS]
    return ids


def make_email(code):
    tail = "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(10))
    return f"tun_{code.lower()}_{tail}"


def make_sub_id():
    return "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(16))


def create_client(code, days):
    """Один клиент с одним subId сразу на всех инбаундах = одна подписка со всеми серверами."""
    email = make_email(code)
    sub_id = make_sub_id()
    expiry_ms = int((datetime.now(timezone.utc) + timedelta(days=days)).timestamp() * 1000)
    ids = inbound_ids()
    if not ids:
        raise RuntimeError("в панели нет включённых инбаундов")

    panel("POST", "/panel/api/clients/add", {
        "client": {
            "email": email,
            "subId": sub_id,
            "expiryTime": expiry_ms,
            "totalGB": 0,
            # Бесплатный месяц — одно устройство плюс запас на смену сети.
            "limitIp": 2,
            "enable": True,
        },
        "inboundIds": ids,
    })
    return email, sub_id, expiry_ms, len(ids)


def client_status(email):
    try:
        return panel("GET", f"/panel/api/clients/traffic/{email}")
    except Exception:
        return None


def extend(email, days):
    return panel("POST", "/panel/api/clients/bulkAdjust", {"emails": [email], "addDays": days})


# Что панель отдаёт при чтении и что ждёт при записи — расходится: id
# приходит числом, а принимается строкой; allowedIPs приходит строкой, а
# принимается списком. Поэтому приводим payload к схеме записи явно, а не
# ловим ошибки по одной.
PANEL_CLIENT_FIELDS = {
    "adTag": str, "allowedIPs": list, "auth": str, "comment": str,
    "created_at": int, "email": str, "enable": bool, "expiryTime": int,
    "flow": str, "group": str, "id": str, "keepAlive": int, "limitIp": int,
    "password": str, "preSharedKey": str, "privateKey": str, "publicKey": str,
    "reset": int, "secret": str, "security": str, "subId": str, "tgId": int,
    "totalGB": int, "updated_at": int,
}


def panel_client_payload(client):
    out = {}
    for key, kind in PANEL_CLIENT_FIELDS.items():
        if key not in client:
            continue
        v = client[key]
        if v is None:
            continue
        if kind is list:
            if isinstance(v, str):
                v = [p.strip() for p in v.split(",") if p.strip()]
            elif not isinstance(v, list):
                v = []
        elif kind is bool:
            v = bool(v)
        elif kind is int:
            try:
                v = int(v)
            except (TypeError, ValueError):
                continue
        else:
            v = str(v)
        out[key] = v
    return out


def set_panel_device_limit(email, n):
    """Привести лимит устройств в панели к купленному тарифу.

    Без этого лимит остаётся общим (LIMIT_IP) и лишнее устройство можно
    подключить в обход нашего счётчика — просто вставив ссылку подписки
    в любой клиент.

    Панель ЗАМЕНЯЕТ запись целиком, а не правит поля, поэтому сначала
    читаем клиента, меняем одно поле и возвращаем всё обратно. И проверяем
    привязку к инбаундам: она умеет молча схлопываться, а ответ приходит
    успешный — это стоило нам однажды отвалившихся клиентов.
    """
    got = panel("GET", f"/panel/api/clients/get/{email}")
    obj = got[0] if isinstance(got, list) else got
    client = dict(obj.get("client") or obj)
    before = list(obj.get("inboundIds") or [])
    # Запас в единицу обязателен: телефон при переходе с Wi-Fi на мобильный
    # какое-то время виден с двух адресов сразу, и жёсткий лимит рвал бы связь
    # честному человеку.
    client = panel_client_payload(client)

    want = n + 1
    if int(client.get("limitIp") or 0) == want:
        return
    client["limitIp"] = want
    panel("POST", f"/panel/api/clients/update/{email}", client)

    after_raw = panel("GET", f"/panel/api/clients/get/{email}")
    after_obj = after_raw[0] if isinstance(after_raw, list) else after_raw
    after = list(after_obj.get("inboundIds") or [])
    if before and len(after) < len(before):
        sys.stderr.write(
            f"привязка схлопнулась у {email}: было {len(before)}, стало {len(after)} — чиню\n")
        panel("POST", "/panel/api/clients/bulkAttach",
              {"emails": [email], "inboundIds": before})


def days_left_of(expiry_ms):
    if not expiry_ms:
        return None
    return max(0, int((expiry_ms / 1000 - time.time()) / 86400))


def referral_code(sub_id):
    """Код приглашения выводится из ключа, отдельно хранить нечего."""
    return "TUN" + sub_id[:6].upper()


def sub_by_referral(con, code):
    """Обратный ход: код -> ключ. LIKE идёт по индексу idx_sub."""
    if not code.startswith("TUN") or len(code) != 9:
        return None
    rows = con.execute(
        "SELECT DISTINCT sub_id FROM activations WHERE sub_id LIKE ?", (code[3:].lower() + "%",)
    ).fetchall()
    return rows[0][0] if len(rows) == 1 else None


def device_limit_of(con, sub_id):
    row = con.execute("SELECT device_limit FROM subs WHERE sub_id=?", (sub_id,)).fetchone()
    return int(row[0]) if row else 1


def set_device_limit(con, sub_id, n):
    con.execute(
        "INSERT INTO subs(sub_id,device_limit,updated) VALUES(?,?,?) "
        "ON CONFLICT(sub_id) DO UPDATE SET device_limit=excluded.device_limit, updated=excluded.updated",
        (sub_id, n, datetime.now(timezone.utc).isoformat()),
    )


def send_mail(to, subject, text):
    """Попросить сайт отправить письмо. Отсюда SMTP наружу закрыт хостером."""
    if not (MAIL_URL and MAIL_SECRET):
        raise RuntimeError("отправка писем не настроена")
    req = urllib.request.Request(
        MAIL_URL,
        data=json.dumps({"to": to, "subject": subject, "text": text}).encode(),
        headers={"Content-Type": "application/json", "X-Tunnelo-Secret": MAIL_SECRET},
        method="POST")
    with urllib.request.urlopen(req, timeout=20) as r:
        if r.status != 200:
            raise RuntimeError(f"сайт не отправил письмо: {r.status}")


def ensure_user(con, email):
    row = con.execute("SELECT id FROM users WHERE email=?", (email,)).fetchone()
    if row:
        return row[0]
    con.execute("INSERT INTO users(email,created) VALUES(?,?)",
                (email, datetime.now(timezone.utc).isoformat()))
    return con.execute("SELECT id FROM users WHERE email=?", (email,)).fetchone()[0]


def new_session(con, user_id):
    token = secrets.token_urlsafe(48)
    con.execute("INSERT INTO sessions(token,user_id,created) VALUES(?,?,?)",
                (token, user_id, datetime.now(timezone.utc).isoformat()))
    return token


def user_by_token(con, token):
    if not token or not TOKEN_RE.match(token):
        return None
    row = con.execute(
        "SELECT s.user_id, u.email FROM sessions s JOIN users u ON u.id=s.user_id "
        "WHERE s.token=?", (token,)).fetchone()
    if row:
        con.execute("UPDATE sessions SET seen=? WHERE token=?",
                    (datetime.now(timezone.utc).isoformat(), token))
    return row


def sub_of_user(con, user_id):
    row = con.execute("SELECT sub_id FROM user_subs WHERE user_id=?", (user_id,)).fetchone()
    return row[0] if row else None


def bind_sub(con, user_id, sub_id):
    """Привязать подписку к человеку, если она ещё ничья."""
    row = con.execute("SELECT user_id FROM user_subs WHERE sub_id=?", (sub_id,)).fetchone()
    if row and row[0] != user_id:
        return False
    con.execute(
        "INSERT INTO user_subs(user_id,sub_id) VALUES(?,?) "
        "ON CONFLICT(user_id) DO UPDATE SET sub_id=excluded.sub_id", (user_id, sub_id))
    return True


def account_state(con, user_id, email):
    """Всё, что человек видит про свой аккаунт: и в кабинете, и в приложении."""
    sub_id = sub_of_user(con, user_id)
    out = {"email": email, "key": sub_id, "subscription": SUB_URI + sub_id if sub_id else None}
    if not sub_id:
        return out
    row = con.execute(
        "SELECT email FROM activations WHERE sub_id=? LIMIT 1", (sub_id,)).fetchone()
    st = client_status(row[0]) if row else None
    expiry = (st or {}).get("expiryTime", 0)
    inv = con.execute(
        "SELECT COUNT(*), COALESCE(SUM(days),0) FROM referrals WHERE referrer_sub=?",
        (sub_id,)).fetchone()
    out.update({
        "active": bool((st or {}).get("enable")),
        "expires": expiry,
        "daysLeft": days_left_of(expiry),
        "devices": devices_used(con, sub_id),
        "deviceLimit": device_limit_of(con, sub_id),
        "referralCode": referral_code(sub_id),
        "invited": inv[0],
        "bonusDays": inv[1],
        "payments": [
            {"date": r[0], "amount": r[1], "plan": r[2], "status": r[3]}
            for r in con.execute(
                "SELECT created, amount, plan, status FROM payments "
                "WHERE user_id=? ORDER BY created DESC LIMIT 20", (user_id,))
        ],
    })
    return out


def devices_used(con, sub_id):
    return con.execute(
        "SELECT COUNT(DISTINCT device) FROM activations WHERE sub_id=?", (sub_id,)
    ).fetchone()[0]


# ---------- подписка ---------------------------------------------------------
# Заголовки sub-сервера, которые обязаны дойти до клиента как есть: в
# Subscription-Userinfo лежит срок и трафик, в Routing — правила маршрутизации.
SUB_PASS_HEADERS = (
    "Profile-Update-Interval",
    "Profile-Title",
    "Subscription-Userinfo",
    "Routing",
    "Routing-Enable",
)


def sub_fetch(sub_id, query=""):
    """Забрать подписку у sub-сервера 3x-ui. -> (status, body_bytes, headers)"""
    url = f"{SUB_UPSTREAM}/sub/{sub_id}" + (("?" + query) if query else "")
    req = urllib.request.Request(url, method="GET")
    req.add_header("User-Agent", "tunnelo-activation")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read(), dict(e.headers)


def sub_filter(body):
    """Оставить в подписке только разрешённые протоколы.

    Тело подписки — base64 от списка ссылок по строке на сервер. Иногда
    sub-сервер отдаёт тот же список открытым текстом, поэтому декодируем
    мягко и возвращаем в том же виде, в каком получили.
    -> (новое тело, сколько оставили, сколько выкинули)
    """
    if not SUB_PROTOCOLS:
        return body, -1, 0

    raw = body.strip()
    was_b64 = False
    if raw and b"://" not in raw:
        try:
            pad = b"=" * (-len(raw) % 4)
            decoded = base64.b64decode(raw + pad)
            was_b64 = True
        except Exception:
            decoded = raw
    else:
        decoded = raw

    kept, dropped = [], 0
    for line in decoded.decode("utf-8", "replace").splitlines():
        t = line.strip()
        if not t:
            continue
        scheme = t.split("://", 1)[0].lower() if "://" in t else ""
        if scheme in SUB_PROTOCOLS:
            kept.append(t)
        else:
            dropped += 1

    out = ("\n".join(kept) + ("\n" if kept else "")).encode()
    if was_b64:
        out = base64.b64encode(out)
    return out, len(kept), dropped


# ---------- HTTP -------------------------------------------------------------
class H(BaseHTTPRequestHandler):
    server_version = "tunnelo-activation/2.0"

    # Часть клиентов подписки сначала стучится HEAD'ом. Базовый обработчик на
    # это отвечает 501, и такой клиент решает, что подписка мертва.
    def do_HEAD(self):
        self.head_only = True
        self.do_GET()

    def _write_body(self, b):
        if getattr(self, "head_only", False):
            return
        self.wfile.write(b)

    def _send(self, code, payload):
        b = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self._write_body(b)

    def log_message(self, fmt, *a):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % a))

    def do_GET(self):
        if self.path == "/health":
            try:
                lst = panel("GET", "/panel/api/inbounds/list")
                enabled = [i for i in lst if i.get("enable", True)]
                app_ok = [i for i in enabled
                          if proto_alias(i.get("protocol")) in SUB_PROTOCOLS] if SUB_PROTOCOLS else enabled
                return self._send(200, {
                    "ok": True,
                    "inbounds": len(enabled),          # всего в панели
                    "appInbounds": len(app_ok),        # столько увидит приложение
                    "subProtocols": SUB_PROTOCOLS,
                })
            except Exception as e:
                return self._send(503, {"ok": False, "error": str(e)})

        if self.path == "/me":
            token = self.headers.get("Authorization", "")
            token = token[7:].strip() if token.startswith("Bearer ") else token.strip()
            con = db()
            try:
                who = user_by_token(con, token)
                if not who:
                    return self._send(401, {"error": "unauthorized"})
                state = account_state(con, who[0], who[1])
                con.commit()
                return self._send(200, state)
            finally:
                con.close()

        m = re.match(r"^/sub/([A-Za-z0-9_\-]+)/?$", self.path.split("?", 1)[0])
        if m:
            return self.serve_sub(m.group(1))

        m = re.match(r"^/status/([A-Za-z0-9_\-]+)$", self.path)
        if m:
            sub_id = m.group(1)
            con = db()
            try:
                row = con.execute(
                    "SELECT email FROM activations WHERE sub_id=?", (sub_id,)).fetchone()
                if not row:
                    return self._send(404, {"error": "unknown key"})
                used = devices_used(con, sub_id)
                limit = device_limit_of(con, sub_id)
                inv = con.execute(
                    "SELECT COUNT(*), COALESCE(SUM(days),0) FROM referrals WHERE referrer_sub=?",
                    (sub_id,)).fetchone()
                claimed = con.execute(
                    "SELECT 1 FROM referrals WHERE referee_sub=?", (sub_id,)).fetchone() is not None
            finally:
                con.close()
            st = client_status(row[0])
            if not st:
                return self._send(404, {"error": "client not found"})
            expiry = st.get("expiryTime", 0)
            return self._send(200, {
                "active": bool(st.get("enable")),
                "daysLeft": days_left_of(expiry),
                "expires": expiry,
                "subscription": SUB_URI + sub_id,
                "up": st.get("up"), "down": st.get("down"),
                "devices": used,
                "deviceLimit": limit,
                "referralCode": referral_code(sub_id),
                "invited": inv[0],
                "bonusDays": inv[1],
                "referralUsed": claimed,
            })

        self._send(404, {"error": "no route"})

    def serve_sub(self, sub_id):
        query = self.path.split("?", 1)[1] if "?" in self.path else ""
        no_filter = "all=1" in query
        try:
            status, body, headers = sub_fetch(sub_id, query)
        except Exception as e:
            sys.stderr.write(f"sub {sub_id}: upstream error: {e}\n")
            return self._send(502, {"error": "subscription unavailable"})

        if status != 200:
            self.send_response(status)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            return self._write_body(body)

        if no_filter:
            kept, dropped = -1, 0
        else:
            body, kept, dropped = sub_filter(body)
            if dropped:
                sys.stderr.write(f"sub {sub_id}: отдал {kept}, отфильтровал {dropped}\n")
            if kept == 0:
                # Пустая подписка стёрла бы у клиента весь список серверов —
                # это заметно хуже, чем лишний сервер, поэтому кричим в лог.
                sys.stderr.write(f"sub {sub_id}: ВНИМАНИЕ, после фильтра "
                                 f"({','.join(SUB_PROTOCOLS)}) не осталось ни одного сервера\n")

        self.send_response(200)
        self.send_header("Content-Type", headers.get("Content-Type", "text/plain; charset=utf-8"))
        for h in SUB_PASS_HEADERS:
            if headers.get(h) is not None:
                self.send_header(h, headers[h])
        # Апстрим подставляет сюда свой 127.0.0.1 — заменяем на внешний адрес.
        self.send_header("Profile-Web-Page-Url", SUB_URI + sub_id)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self._write_body(body)

    def do_POST(self):
        if self.path not in ("/activate", "/extend", "/redeem",
                             "/auth/request", "/auth/verify"):
            return self._send(404, {"error": "no route"})
        n = int(self.headers.get("Content-Length", "0") or 0)
        try:
            body = json.loads(self.rfile.read(n).decode()) if n else {}
        except Exception:
            return self._send(400, {"error": "bad json"})

        if self.path == "/extend":
            return self.do_extend(body)
        if self.path == "/redeem":
            return self.do_redeem(body)
        if self.path == "/auth/request":
            return self.do_auth_request(body)
        if self.path == "/auth/verify":
            return self.do_auth_verify(body)

        return self.do_activate(body)

    def do_activate(self, body):
        code = str(body.get("code", "")).strip().upper()
        device = str(body.get("device", "")).strip()

        if not CODE_RE.match(code):
            return self._send(400, {"error": "bad code format"})
        if not DEVICE_RE.match(device):
            return self._send(400, {"error": "bad device id"})
        promo = PROMO_CODES.get(code)
        if not promo:
            return self._send(404, {"error": "promo not found", "message": "Такого промокода нет"})

        con = db()
        try:
            row = con.execute(
                "SELECT sub_id, email FROM activations WHERE device=? AND code=?", (device, code)
            ).fetchone()
            if row:
                sub_id, email = row
                st = client_status(email)
                if st:
                    expiry = st.get("expiryTime", 0)
                    days_left = max(0, int((expiry / 1000 - time.time()) / 86400)) if expiry else None
                    return self._send(200, {
                        "key": sub_id,
                        "subscription": SUB_URI + sub_id,
                        "expires": expiry,
                        "daysLeft": days_left,
                        "reused": True,
                    })
                con.execute("DELETE FROM activations WHERE device=? AND code=?", (device, code))
                con.commit()

            if promo["limit"]:
                used = con.execute("SELECT COUNT(*) FROM activations WHERE code=?", (code,)).fetchone()[0]
                if used >= promo["limit"]:
                    return self._send(409, {"error": "promo exhausted",
                                            "message": "Промокод больше не действует"})

            email, sub_id, expiry_ms, n_inb = create_client(code, promo["days"])
            con.execute(
                "INSERT INTO activations(device,code,sub_id,email,created) VALUES(?,?,?,?,?)",
                (device, code, sub_id, email, datetime.now(timezone.utc).isoformat()),
            )
            con.commit()
            sys.stderr.write(f"activated {email} sub={sub_id} inbounds={n_inb}\n")
            return self._send(201, {
                "key": sub_id,
                "subscription": SUB_URI + sub_id,
                "expires": expiry_ms,
                "daysLeft": promo["days"],
                "servers": n_inb,
                "reused": False,
            })
        except Exception as e:
            sys.stderr.write(f"activate error: {e}\n")
            return self._send(502, {"error": "panel error", "message": "Сервис временно недоступен"})
        finally:
            con.close()

    # ---------- продление после оплаты --------------------------------------
    def do_extend(self, body):
        """Зовёт сайт после подтверждения платежа. Приложение сюда не ходит.

        Метод раздаёт оплаченные дни, поэтому закрыт секретом. Без секрета в
        окружении он выключен целиком: молча работающий открытый /extend хуже,
        чем выключенный.
        """
        if not EXTEND_SECRET:
            return self._send(503, {"error": "extend disabled",
                                    "message": "Продление не настроено"})
        if not secrets.compare_digest(self.headers.get("X-Tunnelo-Secret", ""), EXTEND_SECRET):
            return self._send(403, {"error": "forbidden"})

        key = str(body.get("key", "")).strip().lower()
        try:
            days = int(body.get("days", 0))
        except (TypeError, ValueError):
            days = 0
        if not KEY_RE.match(key) or not 1 <= days <= 732:
            return self._send(400, {"error": "bad request"})

        con = db()
        try:
            row = con.execute(
                "SELECT email FROM activations WHERE sub_id=? LIMIT 1", (key,)).fetchone()
            if not row:
                return self._send(404, {"error": "unknown key"})
            email = row[0]
            devices = body.get("devices")
            if isinstance(devices, int) and 1 <= devices <= LIMIT_IP:
                set_device_limit(con, key, devices)
                con.commit()
                # Лимит в панели должен совпадать с купленным, иначе лишнее
                # устройство подключается мимо нашего счётчика.
                try:
                    set_panel_device_limit(email, devices)
                except Exception as e:
                    sys.stderr.write(f"лимит в панели не обновлён {key}: {e}\n")
            extend(email, days)
            # Платёж записываем здесь же: кабинет показывает историю оплат,
            # и брать её больше неоткуда — уведомление Enot приходит один раз.
            order = str(body.get("order_id", "")).strip()
            if order:
                owner = con.execute(
                    "SELECT user_id FROM user_subs WHERE sub_id=?", (key,)).fetchone()
                con.execute(
                    "INSERT OR REPLACE INTO payments"
                    "(order_id,user_id,sub_id,amount,plan,days,devices,status,created) "
                    "VALUES(?,?,?,?,?,?,?,?,?)",
                    (order, owner[0] if owner else None, key,
                     float(body.get("amount") or 0), str(body.get("plan") or ""),
                     days, devices if isinstance(devices, int) else None,
                     "paid", datetime.now(timezone.utc).isoformat()))
                con.commit()
        except Exception as e:
            sys.stderr.write(f"ВНИМАНИЕ: оплата прошла, продлить не удалось {key}: {e}\n")
            return self._send(502, {"error": "panel error"})
        finally:
            con.close()

        st = client_status(email) or {}
        expiry = st.get("expiryTime", 0)
        sys.stderr.write(f"extended {email} +{days}d\n")
        return self._send(200, {"ok": True, "key": key, "expires": expiry,
                                "daysLeft": days_left_of(expiry)})

    # ---------- вход по почте -----------------------------------------------
    def do_auth_request(self, body):
        """Выслать одноразовый код. Пароля у нас нет намеренно."""
        email = str(body.get("email", "")).strip().lower()
        if not EMAIL_RE.match(email):
            return self._send(400, {"error": "bad email",
                                    "message": "Проверьте адрес почты."})
        now = time.time()
        con = db()
        try:
            row = con.execute(
                "SELECT sent FROM login_codes WHERE email=?", (email,)).fetchone()
            if row and now - row[0] < CODE_COOLDOWN:
                wait = int(CODE_COOLDOWN - (now - row[0])) or 1
                return self._send(429, {
                    "error": "too soon",
                    "message": f"Письмо уже отправлено. Повторить можно через {wait} с.",
                })
            code = f"{secrets.randbelow(1000000):06d}"
            con.execute(
                "INSERT INTO login_codes(email,code,expires,sent,tries) VALUES(?,?,?,?,0) "
                "ON CONFLICT(email) DO UPDATE SET code=excluded.code, "
                "expires=excluded.expires, sent=excluded.sent, tries=0",
                (email, code, now + CODE_TTL, now))
            con.commit()
        finally:
            con.close()

        try:
            send_mail(
                email, "Код для входа в Tunnelo",
                f"Ваш код: {code}\n\n"
                f"Он действует {CODE_TTL // 60} минут.\n"
                "Если вы не запрашивали вход, просто не отвечайте на это письмо.",
            )
        except Exception as e:
            sys.stderr.write(f"письмо не ушло на {email}: {e}\n")
            return self._send(502, {
                "error": "mail failed",
                "message": "Не удалось отправить письмо. Попробуйте позже.",
            })
        return self._send(200, {"ok": True, "message": "Код отправлен на почту."})

    def do_auth_verify(self, body):
        email = str(body.get("email", "")).strip().lower()
        code = str(body.get("code", "")).strip()
        device = str(body.get("device", "")).strip()
        key = str(body.get("key", "")).strip().lower()
        if not EMAIL_RE.match(email) or not re.fullmatch(r"\d{6}", code):
            return self._send(400, {"error": "bad request",
                                    "message": "Проверьте адрес и код."})

        con = db()
        try:
            row = con.execute(
                "SELECT code, expires, tries FROM login_codes WHERE email=?",
                (email,)).fetchone()
            if not row:
                return self._send(404, {"error": "no code",
                                        "message": "Сначала запросите код."})
            saved, expires, tries = row
            if time.time() > expires:
                return self._send(410, {"error": "expired",
                                        "message": "Код устарел, запросите новый."})
            if tries >= CODE_TRIES:
                return self._send(429, {
                    "error": "too many",
                    "message": "Слишком много попыток. Запросите новый код.",
                })
            if not secrets.compare_digest(saved, code):
                con.execute("UPDATE login_codes SET tries=tries+1 WHERE email=?", (email,))
                con.commit()
                return self._send(403, {"error": "bad code", "message": "Код не подошёл."})
            con.execute("DELETE FROM login_codes WHERE email=?", (email,))

            user_id = ensure_user(con, email)
            # Человек мог пользоваться приложением до регистрации: тогда ключ
            # уже лежит на устройстве. Привязываем его, а не заводим второй.
            mine = sub_of_user(con, user_id)
            if not mine and KEY_RE.match(key or ""):
                if con.execute("SELECT 1 FROM activations WHERE sub_id=?",
                               (key,)).fetchone() and bind_sub(con, user_id, key):
                    mine = key
            if not mine and DEVICE_RE.match(device or ""):
                r = con.execute("SELECT sub_id FROM activations WHERE device=? LIMIT 1",
                                (device,)).fetchone()
                if r and bind_sub(con, user_id, r[0]):
                    mine = r[0]

            token = new_session(con, user_id)
            state = account_state(con, user_id, email)
            con.commit()
        finally:
            con.close()

        state["token"] = token
        sys.stderr.write(f"вход {email}\n")
        return self._send(200, state)

    # ---------- один вход для всех кодов ------------------------------------
    def do_redeem(self, body):
        """Промокод, код переноса и код друга приходят сюда одинаково.

        Человеку незачем разбираться, какой у него код: пусть вводит в одно
        поле, а разбираемся мы.
        """
        code = str(body.get("code", "")).strip()
        device = str(body.get("device", "")).strip()
        key = str(body.get("key", "")).strip().lower()
        if not DEVICE_RE.match(device):
            return self._send(400, {"error": "bad device id"})

        upper = code.upper()
        if upper in PROMO_CODES:
            return self.do_activate({"code": upper, "device": device})

        lower = code.lower()
        if KEY_RE.match(lower):
            return self.attach_device(lower, device)

        con = db()
        try:
            owner = sub_by_referral(con, upper)
        finally:
            con.close()
        if owner:
            return self.claim_referral(key, owner)

        return self._send(404, {"error": "unknown code",
                                "message": "Такого кода нет. Проверьте, что ввели его целиком."})

    # ---------- второе устройство -------------------------------------------
    def attach_device(self, key, device):
        """Подключить ещё одно устройство к существующей подписке."""
        con = db()
        try:
            row = con.execute(
                "SELECT code, email FROM activations WHERE sub_id=? LIMIT 1", (key,)).fetchone()
            if not row:
                return self._send(404, {"error": "unknown key",
                                        "message": "Такого кода нет. Проверьте, что ввели его целиком."})
            code, email = row
            known = con.execute(
                "SELECT 1 FROM activations WHERE sub_id=? AND device=?", (key, device)).fetchone()
            if not known:
                used = devices_used(con, key)
                limit = device_limit_of(con, key)
                if used >= limit:
                    # Предлагать тариф пошире имеет смысл, только пока он есть.
                    if limit < LIMIT_IP:
                        hint = ("Чтобы подключить ещё одно, перейдите на тариф "
                                "с двумя устройствами.")
                    else:
                        hint = "Больше устройств на один ключ подключить нельзя."
                    return self._send(409, {
                        "error": "device limit",
                        "message": f"На этой подписке занято {used} из {limit}. {hint}",
                    })
                # Устройство могло активировать промокод само и завести свою
                # подписку. Перевешиваем его сюда: REPLACE снимает прежнюю
                # строку по (device, code), прежний клиент просто доживает.
                con.execute(
                    "INSERT OR REPLACE INTO activations(device,code,sub_id,email,created) "
                    "VALUES(?,?,?,?,?)",
                    (device, code, key, email, datetime.now(timezone.utc).isoformat()))
                con.commit()
                sys.stderr.write(f"attached device to {key}\n")
        finally:
            con.close()

        st = client_status(email) or {}
        expiry = st.get("expiryTime", 0)
        return self._send(200, {"key": key, "subscription": SUB_URI + key,
                                "expires": expiry, "daysLeft": days_left_of(expiry),
                                "attached": True})

    # ---------- код друга ----------------------------------------------------
    def claim_referral(self, key, owner):
        if not key:
            return self._send(409, {
                "error": "no subscription",
                "message": "Сначала дождитесь, пока подключение настроится, потом введите код друга.",
            })
        if not KEY_RE.match(key):
            return self._send(400, {"error": "bad key"})
        if key == owner:
            return self._send(409, {"error": "own code",
                                    "message": "Это ваш собственный код — он для друзей."})
        con = db()
        try:
            mine = con.execute(
                "SELECT email FROM activations WHERE sub_id=? LIMIT 1", (key,)).fetchone()
            if not mine:
                return self._send(404, {"error": "unknown key"})
            if con.execute("SELECT 1 FROM referrals WHERE referee_sub=?", (key,)).fetchone():
                return self._send(409, {"error": "already claimed",
                                        "message": "Код друга можно ввести только один раз."})
            his = con.execute(
                "SELECT email FROM activations WHERE sub_id=? LIMIT 1", (owner,)).fetchone()
            if not his:
                return self._send(404, {"error": "unknown code"})
            extend(mine[0], REFERRAL_DAYS)
            extend(his[0], REFERRAL_DAYS)
            con.execute(
                "INSERT INTO referrals(referee_sub,referrer_sub,days,created) VALUES(?,?,?,?)",
                (key, owner, REFERRAL_DAYS, datetime.now(timezone.utc).isoformat()))
            con.commit()
            sys.stderr.write(f"referral {key} <- {owner} +{REFERRAL_DAYS}d\n")
        except Exception as e:
            sys.stderr.write(f"referral error: {e}\n")
            return self._send(502, {"error": "panel error",
                                    "message": "Не получилось начислить дни. Попробуйте позже."})
        finally:
            con.close()
        return self._send(200, {
            "ok": True, "days": REFERRAL_DAYS,
            "message": f"Готово: вам и другу начислено по {REFERRAL_DAYS} дней.",
        })

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


if __name__ == "__main__":
    db().close()
    try:
        n = len(inbound_ids())
        print(f"панель ответила, инбаундов: {n}", file=sys.stderr)
    except Exception as e:
        print(f"!! панель недоступна: {e}", file=sys.stderr)
    print(f"activation service on :{PORT}", file=sys.stderr)
    print(f"промокоды: {', '.join(PROMO_CODES)}", file=sys.stderr)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
