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
srv.shutdown()

print()
print(f"провалов: {len(fails)}")
sys.exit(1 if fails else 0)
