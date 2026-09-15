#!/usr/bin/env bash
# Выкат сервиса активации на сервер: бэкап → копия → проверка синтаксиса →
# рестарт → журнал → список промокодов. Запуск из корня репозитория:
#   server/deploy.sh
# Нужен SSH-ключ, добавленный на сервер (ssh-copy-id root@78.17.33.149).
set -euo pipefail

HOST=root@78.17.33.149
DIR=/opt/tunnelo
SRC="$(cd "$(dirname "$0")" && pwd)/activation-3xui.py"
STAMP=$(date +%Y%m%d-%H%M)

scp -q "$SRC" "$HOST:$DIR/activation-3xui.py.new"
ssh "$HOST" "set -e; cd $DIR
  python3 -m py_compile activation-3xui.py.new
  cp activation-3xui.py activation-3xui.py.bak-$STAMP
  mv activation-3xui.py.new activation-3xui.py
  chmod 700 activation-3xui.py
  systemctl restart tunnelo-activation
  sleep 3
  set -a; . /etc/default/tunnelo-activation; set +a
  # Не поднялся или /health не отвечает → откат на бэкап, и скрипт красный.
  if ! systemctl is-active --quiet tunnelo-activation || ! curl -fsS -m 10 http://127.0.0.1:\$PORT/health >/dev/null; then
    echo 'СЕРВИС НЕ ПОДНЯЛСЯ — откатываю'
    journalctl -u tunnelo-activation -n 20 --no-pager -o cat
    cp activation-3xui.py.bak-$STAMP activation-3xui.py
    systemctl restart tunnelo-activation
    exit 1
  fi
  echo \"сервис: \$(systemctl is-active tunnelo-activation), /health отвечает\"
  journalctl -u tunnelo-activation -n 3 --no-pager -o cat
  python3 activation-3xui.py promo list"
