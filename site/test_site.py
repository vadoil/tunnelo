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


if __name__ == "__main__":
    unittest.main(verbosity=1)
