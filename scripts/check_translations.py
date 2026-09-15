#!/usr/bin/env python3
"""Сверяет файлы переводов приложения с базовым en.i18n.json.

Запуск:  /opt/homebrew/bin/python3.11 scripts/check_translations.py

Проверяет для каждого языка:
  - файл читается как JSON;
  - набор ключей совпадает с базовым (нет лишних, нет пропущенных);
  - у ключей-карт ((map)) совпадают внутренние ключи;
  - плейсхолдеры ({name}, $n, ${tap(...)}) и ссылки (@:path) сохранены;
  - строка не осталась английской там, где в базе она осмысленная
    (предупреждение, не ошибка — часть слов вроде DNS и TLS не переводится).

Коды возврата: 0 — всё сошлось, 1 — есть ошибки.
"""
import json
import os
import re
import sys

BASE = "en"
DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "translations")

PLACEHOLDER = re.compile(r"\{[a-zA-Z_][\w]*\}|\$\{[^}]+\}|\$[a-zA-Z_]\w*")
# точка в конце предложения не входит в ссылку: «@:common.appTitle.» — это ссылка плюс точка
LINK = re.compile(r"@:\w+(?:\.\w+)*")


def flatten(node, prefix=""):
    """Разворачивает дерево переводов в плоский словарь путь → строка."""
    out = {}
    if isinstance(node, dict):
        for key, value in node.items():
            out.update(flatten(value, f"{prefix}.{key}" if prefix else key))
    elif isinstance(node, list):
        for i, value in enumerate(node):
            out.update(flatten(value, f"{prefix}[{i}]"))
    elif isinstance(node, str):
        out[prefix] = node
    return out


# у rich-текста подпись внутри скобок переводится: ${tos(Terms of service)} →
# ${tos(Условия обслуживания)}. Сравниваем только имя плейсхолдера.
LABEL = re.compile(r"\$\{(\w+)\([^}]*\)\}")


def placeholders(text):
    text = LABEL.sub(r"${\1}", text)
    return sorted(PLACEHOLDER.findall(text)) + sorted(LINK.findall(text))


def main():
    base_path = os.path.join(DIR, f"{BASE}.i18n.json")
    with open(base_path, encoding="utf-8") as fh:
        base = flatten(json.load(fh))

    files = sorted(f for f in os.listdir(DIR) if f.endswith(".i18n.json"))
    errors = 0
    print(f"База: {BASE}.i18n.json — {len(base)} строк\n")

    for name in files:
        code = name[: -len(".i18n.json")]
        if code == BASE:
            continue
        path = os.path.join(DIR, name)
        try:
            with open(path, encoding="utf-8") as fh:
                data = flatten(json.load(fh))
        except Exception as exc:  # noqa: BLE001
            print(f"  {code}: НЕ ЧИТАЕТСЯ — {exc}")
            errors += 1
            continue

        missing = sorted(set(base) - set(data))
        # у славянских и тюркских языков больше форм множественного числа,
        # чем у английского: few/many сверх one/other — это норма, не лишнее.
        plural_forms = {"zero", "one", "two", "few", "many", "other"}
        extra = sorted(
            k for k in set(data) - set(base)
            if k.rsplit(".", 1)[-1] not in plural_forms
        )
        bad_ph = []
        untranslated = 0
        for key in sorted(set(base) & set(data)):
            # в формах множественного числа $n есть не везде: по-арабски
            # «один день» — слово без числа. Это не ошибка.
            if key.rsplit(".", 1)[-1] in plural_forms:
                continue
            if placeholders(base[key]) != placeholders(data[key]):
                bad_ph.append(key)
            if len(base[key]) > 12 and base[key] == data[key]:
                untranslated += 1

        problems = []
        if missing:
            problems.append(f"нет {len(missing)} ключей (напр. {missing[0]})")
        if extra:
            problems.append(f"лишних {len(extra)} (напр. {extra[0]})")
        if bad_ph:
            problems.append(f"плейсхолдеры разошлись в {len(bad_ph)} (напр. {bad_ph[0]})")

        if problems:
            errors += 1
            print(f"  {code}: " + "; ".join(problems))
        else:
            tail = f", без перевода {untranslated}" if untranslated else ""
            print(f"  {code}: сходится, {len(data)} строк{tail}")

    print()
    if errors:
        print(f"Ошибок: {errors}")
        return 1
    print("Все файлы переводов сходятся с базой.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
