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


if __name__ == "__main__":
    unittest.main(verbosity=1)
