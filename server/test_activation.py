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
con.execute("INSERT INTO activations VALUES('devA','ROMAN1','abc123def4567890','e@a','now')")
con.commit()
code = m.referral_code("abc123def4567890")
ok(code == "TUNABC123", f"код приглашения выводится из ключа: {code}")
ok(m.sub_by_referral(con, code) == "abc123def4567890", "по коду находится ключ")
ok(m.sub_by_referral(con, "TUNZZZZZZ") is None, "чужой код не находится")
ok(m.sub_by_referral(con, "ROMAN1") is None, "промокод не путается с реферальным")

# --- лимит устройств ---------------------------------------------------------
ok(m.device_limit_of(con, "abc123def4567890") == 1, "по умолчанию одно устройство")
m.set_device_limit(con, "abc123def4567890", 2); con.commit()
ok(m.device_limit_of(con, "abc123def4567890") == 2, "купленный лимит сохраняется")
ok(m.devices_used(con, "abc123def4567890") == 1, "занято одно устройство")
con.execute("INSERT INTO activations VALUES('devB','ROMAN1','abc123def4567890','e@a','now')")
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

# --- промокоды живут в базе, не в коде ---------------------------------------
con = m.db()
ok(m.promo_get(con, "ROMAN1") == {"days": 30, "limit": 1, "note": "Роман, приглашение"},
   "коды из словаря засеяны в базу при старте")
ok(m.promo_get(con, "PARDAUTO") is None,
   "общий бесплатный код в посеве не появляется")
ok(m.promo_get(con, "NEMA") is None, "неизвестного кода в базе нет")
m.promo_add(con, "zed42", 10, 1, "тест"); con.commit()
ok(m.promo_get(con, "ZED42") == {"days": 10, "limit": 1, "note": "тест"},
   "код добавляется в базу и приводится к верхнему регистру")
try:
    m.promo_add(con, "ab", 10, 0, ""); bad = False
except ValueError:
    bad = True
ok(bad, "код короче 4 символов не добавляется")
lst = {p["code"]: p for p in m.promo_list(con)}
ok("ZED42" in lst and lst["ROMAN1"]["used"] == 2,
   "в списке есть добавленный код и счётчик использований")
ok(m.promo_cli(["add", "cli1", "5", "2", "из", "консоли"]) == 0
   and m.promo_get(con, "CLI1") == {"days": 5, "limit": 2, "note": "из консоли"},
   "консольная команда добавляет код")
ok(m.promo_cli(["bogus"]) == 2, "непонятная консольная команда объясняет, как надо")
con.close()

m.create_client = lambda code, days: (f"tun_{code.lower()}_test", "zed42abcdef01234", 0, 1)
st, b = post("/activate", {"code": "zed42", "device": "device0002"})
ok(st == 201 and b.get("key") == "zed42abcdef01234", f"код из базы активируется без перезапуска ({st})")
st, b = post("/redeem", {"code": "zed42", "device": "device0003"})
ok(st == 409 and "больше не действует" in b.get("message", ""),
   f"/redeem узнаёт код из базы и держит лимит ({st})")

# --- логин и пароль ----------------------------------------------------------
# Почту наружу не пускаем: подменяем отправку и смотрим, что ушло.
sent = []
m.send_mail = lambda to, subject, text: sent.append((to, subject, text))

ok(m.check_password(m.hash_password("parol12345"), "parol12345"), "пароль сходится со своим хешем")
ok(not m.check_password(m.hash_password("parol12345"), "parol1234"), "чужой пароль не подходит")
ok(not m.check_password("", "parol12345"), "пустой хеш никого не пускает")
ok(not m.check_password("мусор", "parol12345"), "испорченный хеш не ломает вход")

con = m.db()
uid = m.ensure_user(con, "petrov@mail.ru")
login1 = m.unique_login(con, "petrov@mail.ru")
ok(login1 == "petrov", f"логин выводится из адреса: {login1}")
con.execute("UPDATE users SET login=? WHERE id=?", ("petrov", uid))
uid2 = m.ensure_user(con, "petrov@bk.ru")
login2 = m.unique_login(con, "petrov@bk.ru")
ok(login2 != "petrov" and login2.startswith("petrov"), f"занятый логин получает номер: {login2}")
creds = m.issue_credentials(con, uid2, "petrov@bk.ru")
ok(creds is not None and len(creds[1]) >= 8, "пара логин/пароль выдаётся")
ok(m.issue_credentials(con, uid2, "petrov@bk.ru") is None,
   "готовую пару повторная выдача не трогает")
con.commit()
their_login, their_password = creds
con.close()

st, b = post("/auth/login", {"login": their_login, "password": their_password})
ok(st == 200 and b.get("token"), f"вход по логину и паролю ({st})")
ok(b.get("login") == their_login and b.get("hasPassword") is True,
   "кабинет знает логин и что пароль задан")
st, b = post("/auth/login", {"login": their_login, "password": "не тот"})
ok(st == 403, f"неверный пароль не пускает ({st})")
st, b = post("/auth/login", {"login": "никого-нет", "password": their_password})
ok(st == 403 and "Логин или пароль" in b.get("message", ""),
   "неизвестный логин отвечает так же, как неверный пароль")
st, b = post("/auth/login", {"login": "petrov@bk.ru", "password": their_password})
ok(st == 200, f"войти можно и адресом почты ({st})")

sent.clear()
st, b = post("/auth/forgot", {"email": "petrov@bk.ru"})
ok(st == 200 and len(sent) == 1, f"ссылка на смену пароля уходит письмом ({st})")
link_token = sent[0][2].split("token=")[1].split()[0] if sent else ""
ok("/cabinet/reset?token=" in sent[0][2], "в письме ссылка на смену пароля")
st, b = post("/auth/forgot", {"email": "petrov@bk.ru"})
ok(st == 200 and len(sent) == 1, "второе письмо подряд не шлём")
sent.clear()
st, b = post("/auth/forgot", {"email": "никого@нет.рф"})
ok(st == 200 and not sent, "про чужой адрес отвечаем так же и письма не шлём")

st, b = post("/auth/reset", {"token": link_token, "password": "корот"})
ok(st == 400, f"короткий пароль не принимается ({st})")
st, b = post("/auth/reset", {"token": link_token, "password": "новыйпароль1"})
ok(st == 200 and b.get("token"), f"пароль меняется по ссылке ({st})")
st, b = post("/auth/reset", {"token": link_token, "password": "ещёодин123"})
ok(st == 409, f"ссылка одноразовая ({st})")
st, b = post("/auth/login", {"login": their_login, "password": "новыйпароль1"})
ok(st == 200, f"вход новым паролем ({st})")
new_token = b.get("token")
st, b = post("/auth/login", {"login": their_login, "password": their_password})
ok(st == 403, "старый пароль больше не работает")

st, b = post("/auth/password", {"current": "новыйпароль1", "password": "третийпароль1"},
             {"Authorization": "Bearer " + new_token})
ok(st == 200, f"пароль меняется из кабинета ({st})")
st, b = post("/auth/password", {"current": "мимо", "password": "четвёртый1234"},
             {"Authorization": "Bearer " + new_token})
ok(st == 403, f"без текущего пароля смена не проходит ({st})")
st, b = post("/auth/password", {"current": "третийпароль1", "password": "пятый12345"},
             {"Authorization": "Bearer " + "z" * 48})
ok(st == 401, f"без сессии смена пароля не проходит ({st})")

srv.shutdown()

print()
print(f"провалов: {len(fails)}")
sys.exit(1 if fails else 0)
