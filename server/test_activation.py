import importlib.util, os, sqlite3, sys, tempfile, json, threading, time, urllib.request, urllib.error

tmp = tempfile.mkdtemp()
os.environ.update(
    PANEL_URL="http://127.0.0.1:9/x", PANEL_TOKEN="t", SUB_URI="http://s/sub/",
    DB_PATH=os.path.join(tmp, "a.db"), PORT="18099",
    EXTEND_SECRET="testsecret", REFERRAL_DAYS="15", LIMIT_IP="3",
)
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("act", os.path.join(here, "activation-3xui.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

ok = lambda c, msg: print(("  ок  " if c else "ПАДАЕТ") + "  " + msg) or (c or fails.append(msg))
fails = []

# --- код приглашения ходит в обе стороны ------------------------------------
con = m.db()
con.execute("INSERT INTO activations VALUES('devA','PARDAUTO','abc123def4567890','e@a','now')")
con.commit()
code = m.referral_code("abc123def4567890")
ok(code == "TUNABC123", f"код приглашения выводится из ключа: {code}")
ok(m.sub_by_referral(con, code) == "abc123def4567890", "по коду находится ключ")
ok(m.sub_by_referral(con, "TUNZZZZZZ") is None, "чужой код не находится")
ok(m.sub_by_referral(con, "PARDAUTO") is None, "промокод не путается с реферальным")

# --- лимит устройств ---------------------------------------------------------
ok(m.device_limit_of(con, "abc123def4567890") == 1, "по умолчанию одно устройство")
m.set_device_limit(con, "abc123def4567890", 2); con.commit()
ok(m.device_limit_of(con, "abc123def4567890") == 2, "купленный лимит сохраняется")
ok(m.devices_used(con, "abc123def4567890") == 1, "занято одно устройство")
con.execute("INSERT INTO activations VALUES('devB','PARDAUTO','abc123def4567890','e@a','now')")
con.commit()
ok(m.devices_used(con, "abc123def4567890") == 2, "второе устройство посчиталось")
con.close()

# --- форма ключа -------------------------------------------------------------
ok(bool(m.KEY_RE.match("abc123def4567890")), "ключ 16 символов принимается")
ok(not m.KEY_RE.match("ABC123DEF4567890"), "ключ в верхнем регистре не принимается")
ok(not m.KEY_RE.match("short"), "короткая строка ключом не считается")

# --- сервер: защита /extend --------------------------------------------------
srv = m.ThreadingHTTPServer(("127.0.0.1", 18099), m.H)
threading.Thread(target=srv.serve_forever, daemon=True).start(); time.sleep(0.3)

def post(path, body, headers=None):
    r = urllib.request.Request("http://127.0.0.1:18099" + path,
                               data=json.dumps(body).encode(), method="POST",
                               headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(r, timeout=5) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

st, _ = post("/extend", {"key": "abc123def4567890", "days": 30})
ok(st == 403, f"/extend без секрета отвергается ({st})")
st, _ = post("/extend", {"key": "abc123def4567890", "days": 30}, {"X-Tunnelo-Secret": "wrong"})
ok(st == 403, f"/extend с чужим секретом отвергается ({st})")
st, _ = post("/extend", {"key": "нехороший", "days": 30}, {"X-Tunnelo-Secret": "testsecret"})
ok(st == 400, f"/extend с кривым ключом отвергается ({st})")
st, _ = post("/extend", {"key": "zzz123def4567890", "days": 30}, {"X-Tunnelo-Secret": "testsecret"})
ok(st == 404, f"/extend по неизвестному ключу — 404 ({st})")
st, b = post("/redeem", {"code": "НЕТТАКОГО", "device": "device0001"})
ok(st == 404 and "Такого кода нет" in b.get("message", ""), "неизвестный код объясняет, что делать")
st, b = post("/redeem", {"code": "TUNABC123", "device": "device0001", "key": ""})
ok(st == 409 and "дождитесь" in b.get("message", ""), "код друга без подписки просит подождать")
st, b = post("/redeem", {"code": "TUNABC123", "device": "device0001", "key": "abc123def4567890"})
ok(st == 409 and "собственный" in b.get("message", ""), "свой же код не засчитывается")
st, _ = post("/nonexistent", {})
ok(st == 404, "лишних маршрутов не появилось")


# --- вход по почте -----------------------------------------------------------
sent = []
m.send_mail = lambda to, subject, text: sent.append((to, text))
m.MAIL_URL, m.MAIL_SECRET = "http://stub", "s"
# Панели в тестах нет: подменяем её ответ, иначе запрос к ней висит до таймаута.
m.client_status = lambda email: {"enable": True,
                                 "expiryTime": int((time.time() + 30 * 86400) * 1000)}

st, b = post("/auth/request", {"email": "не-адрес"})
ok(st == 400, f"кривой адрес почты отвергается ({st})")
st, b = post("/auth/verify", {"email": "a@b.ru", "code": "123456"})
ok(st == 404 and "запросите код" in b.get("message", ""), "вход без кода объясняет, что делать")

st, b = post("/auth/request", {"email": "a@b.ru"})
ok(st == 200 and len(sent) == 1, f"код отправлен ({st})")
code = sent[0][1].split("Ваш код: ")[1].split("\n")[0]
ok(len(code) == 6 and code.isdigit(), f"код шестизначный: {code}")

st, b = post("/auth/request", {"email": "a@b.ru"})
ok(st == 429, f"второе письмо подряд не уходит ({st})")

st, b = post("/auth/verify", {"email": "a@b.ru", "code": "000000"})
ok(st == 403, f"неверный код отвергается ({st})")

st, b = post("/auth/verify", {"email": "a@b.ru", "code": code,
                              "key": "abc123def4567890"})
ok(st == 200 and b.get("token"), "верный код пускает и выдаёт токен")
ok(b.get("key") == "abc123def4567890", "существующая подписка привязалась к аккаунту")
ok(b.get("email") == "a@b.ru", "аккаунт помнит почту")
token = b["token"]

st, b = post("/auth/verify", {"email": "a@b.ru", "code": code})
ok(st == 404, f"код одноразовый ({st})")

def get(path, headers=None):
    r = urllib.request.Request("http://127.0.0.1:18099" + path, headers=headers or {})
    try:
        with urllib.request.urlopen(r, timeout=5) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

st, _ = get("/me")
ok(st == 401, f"кабинет без токена закрыт ({st})")
st, _ = get("/me", {"Authorization": "Bearer notarealtokenatall_0123456789abcdefXYZ"})
ok(st == 401, f"чужой токен не пускает ({st})")
st, b = get("/me", {"Authorization": "Bearer " + token})
ok(st == 200 and b.get("email") == "a@b.ru", "по токену кабинет открывается")
ok(b.get("referralCode") == "TUNABC123", "в кабинете есть код приглашения")

srv.shutdown()

print()
print(f"провалов: {len(fails)}")
sys.exit(1 if fails else 0)
