#!/bin/bash
# Одноразовый выгрузчик свежих скринов с iPhone через нестабильный USB.
# Ждёт появления устройства, перезапускает iproxy и сразу тянет последние PNG.
cd "$(dirname "$0")" || exit 1
mkdir -p screens
DEADLINE=$((SECONDS + 480))

while [ $SECONDS -lt $DEADLINE ]; do
    if idevice_id -l >/dev/null 2>&1 && [ -n "$(idevice_id -l)" ]; then
        pkill -f "iproxy 2222" 2>/dev/null
        sleep 1
        nohup iproxy 2222:22 >/tmp/iproxy.log 2>&1 &
        sleep 3
        if ./iphone-ssh.sh "echo SSH_OK" 2>/dev/null | grep -q SSH_OK; then
            echo "=== СВЯЗЬ ЕСТЬ, тянем список ==="
            ./iphone-ssh.sh "ls -t /var/mobile/Media/DCIM/100APPLE/ | head -12" 2>/dev/null | tail -12
            LIST=$(./iphone-ssh.sh "ls -t /var/mobile/Media/DCIM/100APPLE/ | head -12" 2>/dev/null | grep -E '^IMG_[0-9]+\.(PNG|png|JPG|jpg)$')
            for f in $LIST; do
                if [ -s "screens/$f" ]; then echo "уже есть: $f"; continue; fi
                echo "тяну: $f"
                ./iphone-ssh.sh "base64 /var/mobile/Media/DCIM/100APPLE/$f" 2>/dev/null \
                    | grep -E '^[A-Za-z0-9+/=]+$' | tr -d '\r' | base64 -d > "screens/$f" 2>/dev/null
                if [ -s "screens/$f" ] && file "screens/$f" | grep -qiE 'PNG|JPEG'; then
                    echo "  ок: $(du -h screens/$f | cut -f1)"
                else
                    echo "  СБОЙ, удаляю битый файл"; rm -f "screens/$f"
                fi
            done
            ls -la screens/ | tail -15
            exit 0
        fi
        echo "$(date +%H:%M:%S) устройство есть, SSH не поднялся — повтор"
    else
        echo "$(date +%H:%M:%S) телефона нет в USB"
    fi
    sleep 10
done
echo "ТАЙМАУТ: телефон так и не дал стабильной связи за 8 минут"
exit 1
