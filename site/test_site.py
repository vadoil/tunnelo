"""Проверки сайта без сети. Запуск: /opt/homebrew/bin/python3.11 site/test_site.py

Главное здесь — маршрут /internal/mail: через него сервис активации шлёт
коды входа. Он уже пропадал при рефакторинге, и люди молча переставали
получать письма. Тест ловит именно это: без секрета — 403, а не 404.
"""
import os
import sys
import unittest

os.environ.setdefault("TUNNELO_MAIL_SECRET", "test-secret")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.chdir(os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient  # noqa: E402

import app as site  # noqa: E402


class InternalMail(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(site.app)

    def test_route_exists_and_is_closed_by_secret(self):
        r = self.client.post("/internal/mail", json={"to": "a@b.ru", "text": "x"})
        self.assertEqual(r.status_code, 403, "маршрут /internal/mail потерян или открыт без секрета")

    def test_wrong_secret_forbidden(self):
        r = self.client.post(
            "/internal/mail",
            json={"to": "a@b.ru", "text": "x"},
            headers={"X-Tunnelo-Secret": "wrong"},
        )
        self.assertEqual(r.status_code, 403)

    def test_bad_request_with_secret(self):
        r = self.client.post(
            "/internal/mail",
            json={"to": "no-at-sign", "text": ""},
            headers={"X-Tunnelo-Secret": "test-secret"},
        )
        self.assertEqual(r.status_code, 400)


class Pages(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(site.app)

    def test_health(self):
        self.assertEqual(self.client.get("/health").status_code, 200)

    def test_no_free_trial_promises(self):
        html = self.client.get("/").text
        self.assertNotIn("бесплатно", html.lower())
        self.assertIn("−33%", html)


class Cabinet(unittest.TestCase):
    """Вход по логину и паролю и восстановление по ссылке (16.09.2026)."""

    def setUp(self):
        self.client = TestClient(site.app)

    def test_cabinet_link_in_header(self):
        html = self.client.get("/").text
        self.assertIn('href="/cabinet"', html, "из шапки не попасть в кабинет")

    def test_login_form_asks_for_password(self):
        html = self.client.get("/cabinet").text
        self.assertIn('action="/cabinet/login"', html)
        self.assertIn('name="password"', html)
        self.assertIn("/cabinet/forgot", html, "нет ссылки «Забыли пароль»")

    def test_forgot_page_opens(self):
        r = self.client.get("/cabinet/forgot")
        self.assertEqual(r.status_code, 200)
        self.assertIn('action="/cabinet/forgot"', r.text)

    def test_reset_without_token_explains(self):
        r = self.client.get("/cabinet/reset")
        self.assertEqual(r.status_code, 200)
        self.assertIn("Ссылка неполная", r.text)

    def test_reset_with_token_shows_form(self):
        r = self.client.get("/cabinet/reset?token=" + "a" * 40)
        self.assertIn('name="password2"', r.text)

    def test_reset_mismatch_is_caught_before_service(self):
        r = self.client.post("/cabinet/reset", data={
            "token": "a" * 40, "password": "parol12345", "password2": "drugoy12345"})
        self.assertEqual(r.status_code, 200)
        self.assertIn("не совпали", r.text)

    def test_password_change_without_session_goes_to_login(self):
        r = self.client.post("/cabinet/password", data={
            "current": "x", "password": "parol12345", "password2": "parol12345"},
            follow_redirects=False)
        self.assertEqual(r.status_code, 303)
        self.assertEqual(r.headers["location"], "/cabinet")


class Languages(unittest.TestCase):
    """Девять языков сайта: ключи у всех одинаковые, иначе страница
    показывает русскую фразу среди чужих или падает на .format()."""

    def setUp(self):
        self.client = TestClient(site.app)
        import i18n
        self.i18n = i18n

    def test_every_language_has_same_keys(self):
        base = set(self.i18n.RU)
        for code, strings in self.i18n.STRINGS.items():
            missing = base - set(strings)
            extra = set(strings) - base
            self.assertFalse(missing, f"{code}: нет ключей {sorted(missing)[:3]}")
            self.assertFalse(extra, f"{code}: лишние ключи {sorted(extra)[:3]}")

    def test_placeholders_survive_translation(self):
        import re
        holes = lambda s: sorted(re.findall(r"\{\w+\}", s))
        for code, strings in self.i18n.STRINGS.items():
            for key, ru in self.i18n.RU.items():
                if key in strings:
                    self.assertEqual(holes(ru), holes(strings[key]),
                                     f"{code}.{key}: плейсхолдеры разошлись")

    def test_language_switch_changes_page(self):
        ru = self.client.get("/").text
        en = self.client.get("/?lang=en").text
        self.assertIn("Выбрать тариф", ru)
        self.assertIn("Choose a plan", en)
        self.assertNotIn("Выбрать тариф", en)

    def test_unknown_language_falls_back_to_russian(self):
        html = self.client.get("/?lang=xx").text
        self.assertIn("Выбрать тариф", html)

    def test_choice_is_remembered(self):
        r = self.client.get("/?lang=en")
        self.assertEqual(r.cookies.get("tunnelo_lang"), "en")

    def test_every_language_renders(self):
        for code, _ in self.i18n.LANGS:
            r = self.client.get(f"/?lang={code}")
            self.assertEqual(r.status_code, 200, f"главная не открылась на {code}")
            r = self.client.get(f"/cabinet?lang={code}")
            self.assertEqual(r.status_code, 200, f"кабинет не открылся на {code}")


class Coupons(unittest.TestCase):
    """Скидочные коды. Ошибка здесь стоит денег в обе стороны: лишний ноль в
    проценте раздаёт подписки даром, потерянный код берёт полную цену.

    Коды берём свои, а не боевые: открытые скидки меняются без выката, и
    тест не должен падать оттого, что код закрыли."""

    def setUp(self):
        import json as _json
        import tempfile
        self.file = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        _json.dump({
            "HALF": {"off": 50},
            "ALMOSTFREE": {"off": 90, "until": "2999-01-01"},
            "LASTYEAR": {"off": 50, "until": "2020-01-01"},
            "TOOMUCH": {"off": 100},
        }, self.file)
        self.file.close()
        self.saved_path = site.COUPONS_PATH
        site.COUPONS_PATH = self.file.name
        site._COUPONS["mtime"] = -1.0

    def tearDown(self):
        site.COUPONS_PATH = self.saved_path
        site._COUPONS["mtime"] = -1.0
        os.unlink(self.file.name)

    def test_known_code_cuts_price(self):
        price, code = site.apply_coupon(299, "almostfree")
        self.assertEqual(code, "ALMOSTFREE", "код не сработал — регистр или чтение файла")
        self.assertEqual(price, 30, "299 ₽ со скидкой 90% — это 30 ₽ (округляем вверх)")
        self.assertEqual(site.apply_coupon(499, "HALF")[0], 250)

    def test_unknown_code_keeps_price(self):
        self.assertEqual(site.apply_coupon(299, "нетакого"), (299, None))
        self.assertEqual(site.apply_coupon(299, ""), (299, None))

    def test_expired_code_ignored(self):
        self.assertIsNone(site.coupon_get("LASTYEAR"), "просроченный код обязан молчать")

    def test_full_discount_refused(self):
        self.assertIsNone(site.coupon_get("TOOMUCH"), "100% — это не скидка, а подарок мимо кассы")

    def test_discount_never_below_rouble(self):
        price, _ = site.apply_coupon(1, "ALMOSTFREE")
        self.assertGreaterEqual(price, 1, "платёж на 0 ₽ касса не примет")


class Downloads(unittest.TestCase):
    """Раздел скачивания: ссылки берутся из latest.json, а не вбиты руками —
    иначе после каждой выкладки сайт показывал бы старую версию.

    Список сборок подменяем целиком: тесты ходить в сеть не должны."""

    RELEASE = {
        "version": "9.9.9",
        "downloads": {
            "android": "https://api.amnez.online/dl/Tunnelo-9.9.9.apk",
            "windows": "https://api.amnez.online/dl/Tunnelo-Setup-9.9.9.exe",
            "macos": "https://api.amnez.online/dl/Tunnelo-macOS-9.9.9.zip",
        },
    }

    def setUp(self):
        self.client = TestClient(site.app)
        self.saved = site.latest_release

    def tearDown(self):
        site.latest_release = self.saved

    def test_links_and_version_on_page(self):
        site.latest_release = lambda: self.RELEASE
        html = self.client.get("/").text
        self.assertIn("Tunnelo-9.9.9.apk", html, "нет ссылки на APK")
        self.assertIn("Tunnelo-Setup-9.9.9.exe", html, "нет ссылки на Windows")
        self.assertIn("Tunnelo-macOS-9.9.9.zip", html, "нет ссылки на macOS")
        self.assertIn("9.9.9", html, "не показан номер версии")

    def test_section_hidden_without_releases(self):
        site.latest_release = lambda: {}
        html = self.client.get("/").text
        self.assertNotIn("Скачать Tunnelo", html, "пустой раздел скачивания не должен рисоваться")

    def test_local_file_wins_over_remote(self):
        """Файл лежит у нас — качаем с tunello.online, а не с api.amnez.online."""
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            saved = site.DOWNLOADS_DIR
            site.DOWNLOADS_DIR = tmp
            try:
                open(os.path.join(tmp, "Tunnelo-9.9.9.apk"), "w").close()
                self.assertEqual(
                    site._local_link("https://api.amnez.online/dl/Tunnelo-9.9.9.apk"),
                    f"{site.SITE_URL}/downloads/Tunnelo-9.9.9.apk",
                )
                # Чего нет на месте — остаётся по прежней ссылке.
                self.assertEqual(
                    site._local_link("https://api.amnez.online/dl/Tunnelo-Setup-9.9.9.exe"),
                    "https://api.amnez.online/dl/Tunnelo-Setup-9.9.9.exe",
                )
            finally:
                site.DOWNLOADS_DIR = saved


if __name__ == "__main__":
    unittest.main(verbosity=1)
