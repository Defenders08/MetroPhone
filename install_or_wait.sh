#!/bin/bash
# Дозор: ждёт стабильный SSH до iPhone, тянет свежие скрины, ставит 0.12.0, ресспринг.
cd "$(dirname "$0")" || exit 1
DEADLINE=$((SECONDS + 1500))   # до 25 минут

try_ssh() {
    ./iphone-ssh.sh "$1" 2>/dev/null | grep -q "$2"
}

while [ $SECONDS -lt $DEADLINE ]; do
    if [ -z "$(idevice_id -l 2>/dev/null)" ]; then
        sleep 12
        continue
    fi
    pkill -f "iproxy 2222" 2>/dev/null
    sleep 1
    nohup iproxy 2222:22 >/tmp/iproxy.log 2>&1 &
    disown
    sleep 3
    if ! try_ssh "echo PING_OK" "PING_OK"; then
        echo "$(date +%H:%M:%S) устройство есть, SSH мимо"
        sleep 15
        continue
    fi

    echo "=== СВЯЗЬ ЕСТЬ ==="

    # 1) свежие скрины (что успеем — то успеем)
    LIST=$(./iphone-ssh.sh "ls -t /var/mobile/Media/DCIM/100APPLE/ | head -8" 2>/dev/null | grep -E '^IMG_')
    mkdir -p screens
    for f in $LIST; do
        [ -s "screens/$f" ] && continue
        ./iphone-ssh.sh "base64 /var/mobile/Media/DCIM/100APPLE/$f" 2>/dev/null \
            | grep -E '^[A-Za-z0-9+/=]+$' | tr -d '\r' | base64 -d > "screens/$f" 2>/dev/null
        if file "screens/$f" | grep -qiE 'PNG|JPEG'; then
            echo "скрин: $f ($(du -h "screens/$f" | cut -f1))"
        else
            rm -f "screens/$f"
        fi
    done

    # 2) установка пакета
    echo "=== ЗАЛИВКА ПАКЕТА ==="
    ./iphone-ssh.sh --push packages/ru.ash.metrophone_0.12.0_iphoneos-arm.deb /tmp/mp_0120.deb >/dev/null 2>&1
    if ! try_ssh "ls -l /tmp/mp_0120.deb" "mp_0120.deb"; then
        echo "ЗАЛИВКА НЕ ПРОШЛА — повтор цикла"
        sleep 10
        continue
    fi
    echo "=== УСТАНОВКА ==="
    ./iphone-ssh.sh "dpkg -i /tmp/mp_0120.deb 2>&1; dpkg -s ru.ash.metrophone | grep Version; rm -f /tmp/mp_0120.deb" 2>/dev/null | tail -4
    echo "=== RESPRING ==="
    ./iphone-ssh.sh "killall SpringBoard" >/dev/null 2>&1
    sleep 18
    ./iphone-ssh.sh "launchctl list | grep SpringBoard; tail -6 /var/mobile/Library/Preferences/metrophone.log" 2>/dev/null | tail -8
    echo "=== УСТАНОВКА ЗАВЕРШЕНА ==="
    exit 0
done
echo "ТАЙМАУТ 25 мин: стабильной связи не было"
exit 1
