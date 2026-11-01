#!/bin/bash
# dev.sh — быстрая разработка MetroPhone по USB (единственный канал).
#
# Ключевые приёмы (облегчают жизнь по сравнению с iphone-ssh.sh):
#   1. Вход по ssh-ключу ~/.ssh/iphone_rsa (лежит в authorized_keys телефона) —
#      без expect и паролей.
#   2. SSH ControlMaster: первое соединение открывает «мастер», все следующие
#      команды едут по нему. Это обходит главное ограничение старого sshd —
#      «через один iproxy проходит только первое соединение»: теперь наоборот,
#      все соединения reuse одно, iproxy не надо перезапускать на каждую команду.
#   3. Мастер живёт 10 минут бездействия (ControlPersist), после — сам закрывается.
#
# Команды:
#   tools/dev.sh cmd "команда"            — выполнить на телефоне
#   tools/dev.sh push ЛОК ФАЙЛ /путь      — передать файл (scp)
#   tools/dev.sh pull /путь ЛОК ФАЙЛ      — забрать файл
#   tools/dev.sh install [deb]            — установить deb (по умолчанию новейший
#                                           из builds/) + respring + хвост журнала
#   tools/dev.sh shot [out.png]           — снимок экрана через shot.request
#                                           (по умолчанию /tmp/mp_shot.png)
#   tools/dev.sh log [N]                  — хвост metrophone.log (по умолчанию 30)
#   tools/dev.sh clearlog                 — обнулить журнал
#   tools/dev.sh open <url|bundleID>      — открыть ссылку/приложение (uiopen)
#   tools/dev.sh pid                      — pid SpringBoard
#   tools/dev.sh alive                    — проверить связь (быстро)
#   tools/dev.sh shell                    — интерактивная сессия

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PORT=2222
CTRL=/tmp/mp-ssh-master
LOG=/var/mobile/Library/Preferences/metrophone.log

# Легаси-алгоритмы: старый sshd iOS 6 не понимает современные по умолчанию
BASE_OPTS="-p $PORT
  -i $HOME/.ssh/iphone_rsa
  -o HostkeyAlgorithms=+ssh-rsa
  -o PubkeyAcceptedAlgorithms=+ssh-rsa
  -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1
  -o MACs=+hmac-sha1,hmac-sha1-96
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o PasswordAuthentication=no
  -o ConnectTimeout=8"
MUX_OPTS="$BASE_OPTS
  -o ControlMaster=auto
  -o ControlPath=$CTRL
  -o ControlPersist=10m"

# Поднять USB-туннель (если порт ещё не слушается — свежий iproxy)
ensure_iproxy() {
    if ! nc -z 127.0.0.1 $PORT 2>/dev/null; then
        pkill -f "iproxy $PORT" 2>/dev/null
        nohup iproxy $PORT:22 >/tmp/iproxy.log 2>&1 &
        sleep 2
        if ! nc -z 127.0.0.1 $PORT 2>/dev/null; then
            echo "ОШИБКА: iproxy не поднялся — телефон подключён по USB?" >&2
            exit 1
        fi
    fi
}

# Мастер-соединение: открывается первым вызовом, дальше все едут по нему.
# Если мастер протух (телефон отваливался) — прибиваем и переоткрываем.
ensure_master() {
    ensure_iproxy
    ssh $MUX_OPTS root@127.0.0.1 "echo ok" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        ssh -O exit -o ControlPath=$CTRL root@127.0.0.1 2>/dev/null
        pkill -f "iproxy $PORT" 2>/dev/null
        sleep 1
        nohup iproxy $PORT:22 >/tmp/iproxy.log 2>&1 &
        sleep 3
        if ! ssh $MUX_OPTS root@127.0.0.1 "echo ok" >/dev/null 2>&1; then
            echo "ОШИБКА: SSH не открылся (ключ/канал). Один раз проверь: ssh -p $PORT root@127.0.0.1" >&2
            exit 1
        fi
    fi
}

# scp использует -P (порт) вместо -p: та же пачка опций с подменой
SCP_OPTS="${MUX_OPTS/-p $PORT/-P $PORT}"

cmd() {
    ensure_master
    ssh $MUX_OPTS root@127.0.0.1 "$1"
}

case "$1" in
    cmd)
        shift
        cmd "$*"
        ;;
    alive)
        if cmd "echo alive" 2>/dev/null | grep -q alive; then echo ЖИВ; else echo НЕТ; exit 1; fi
        ;;
    pid)
        cmd "launchctl list | grep -i springboard"
        ;;
    log)
        N=${2:-30}
        cmd "tail -$N $LOG | tr -d '\r'"
        ;;
    clearlog)
        cmd "echo --- $(date +%H:%M:%S) --- > $LOG"
        ;;
    push)
        ensure_master
        scp $SCP_OPTS "$2" root@127.0.0.1:"$3"
        ;;
    pull)
        ensure_master
        scp $SCP_OPTS root@127.0.0.1:"$2" "$3"
        ;;
    install)
        DEB="$2"
        if [ -z "$DEB" ]; then
            DEB=$(ls -t "$(dirname "$0")/../builds/"ru.ash.metrophone_*_iphoneos-arm.deb 2>/dev/null | grep -v debug | head -1)
        fi
        [ -s "$DEB" ] || { echo "нет deb"; exit 1; }
        TOTAL=$(wc -c < "$DEB" | tr -d ' ')
        echo "ставлю $(basename "$DEB") ($TOTAL байт)"
        ensure_master
        scp $SCP_OPTS "$DEB" root@127.0.0.1:/tmp/metrophone.deb || exit 1
        GOT=$(cmd "wc -c < /tmp/metrophone.deb" | tr -d '\r ' )
        [ "$GOT" = "$TOTAL" ] || { echo "ОШИБКА: на телефоне $GOT из $TOTAL"; exit 1; }
        cmd "dpkg -i /tmp/metrophone.deb 2>&1 | tail -2; rm -f /tmp/metrophone.deb; killall SpringBoard; echo RESPRUNG"
        sleep 20
        cmd "tail -6 $LOG | tr -d '\r'"
        ;;
    shot)
        OUT=${2:-/tmp/mp_shot.png}
        cmd "date > /var/mobile/Library/Caches/metrophone/shot.request" || exit 1
        sleep 4
        # ждём появления свежего файла до 6 с
        for i in 1 2 3; do
            SZ=$(cmd "wc -c < /var/mobile/Library/Caches/metrophone/shot.png 2>/dev/null" | tr -d '\r ')
            [ -n "$SZ" ] && [ "$SZ" != "0" ] && break
            sleep 2
        done
        ensure_master
        scp $SCP_OPTS root@127.0.0.1:/var/mobile/Library/Caches/metrophone/shot.png "$OUT" || exit 1
        echo "$OUT ($(wc -c < "$OUT" | tr -d ' ') байт) — 8214 байт = чёрный кадр (телефон залочен)"
        ;;
    open)
        cmd "uiopen '$2'"
        ;;
    shell)
        ensure_master
        ssh $MUX_OPTS root@127.0.0.1
        ;;
    *)
        echo "dev.sh: команды cmd|alive|pid|log|clearlog|push|pull|install|shot|open|shell — см. шапку файла" >&2
        exit 2
        ;;
esac
