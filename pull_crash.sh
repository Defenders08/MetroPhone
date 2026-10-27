#!/bin/bash
# Тянет свежий крэшлог «Настроек» с iPhone по нестабильному каналу:
# на телефоне лог жмётся gzip, читается dd-чанками по 1 КБ (base64) с повторами.
cd "$(dirname "$0")" || exit 1
mkdir -p crashlogs

ssh_run() { ./iphone-ssh.sh "$1" 2>/dev/null | grep -vE '^(spawn |Warning:|root@)'; }

DEADLINE=$((SECONDS + 3600))
LINK=NO
while [ $SECONDS -lt $DEADLINE ]; do
    if [ -z "$(idevice_id -l 2>/dev/null)" ]; then sleep 15; continue; fi
    pkill -f "iproxy 2222" 2>/dev/null; sleep 1
    nohup iproxy 2222:22 >/tmp/iproxy.log 2>&1 & disown
    sleep 3
    if ssh_run "echo P" | grep -q P; then LINK=YES; echo "канал жив"; break; fi
    sleep 12
done
[ "$LINK" = YES ] || { echo "канала не дождались"; exit 1; }

# свежий крэшлог Preferences (Настройки) — в двух возможных местах.
# grep -v spawn: expect рисует в выводе строку «spawn ssh …» с теми же путями
F=$(ssh_run "ls -t /var/logs/CrashReporter/ /var/mobile/Library/Logs/CrashReporter/ 2>/dev/null | grep -iE '^Preferences' | head -1" | grep -v spawn | grep -iE '^Preferences' | head -1)
if [ -z "$F" ]; then
    echo "крэшлогов Preferences не найдено:"
    ssh_run "ls -t /var/logs/CrashReporter/ 2>/dev/null | head -8" | head -8
    exit 2
fi
echo "крэшлог: $F"

# сжать на телефоне и узнать размер
SZ=$(ssh_run "gzip -c -9 '/var/logs/CrashReporter/$F' > /tmp/crash.gz 2>/dev/null || gzip -c -9 '/var/mobile/Library/Logs/CrashReporter/$F' > /tmp/crash.gz; wc -c < /tmp/crash.gz" | grep -E '^[0-9]+$' | tail -1)
echo "gz: $SZ байт"
[ -n "$SZ" ] || { echo "не смогли сжать"; exit 1; }

# читаем dd-чанками по 1024 байта, каждый с повторами
CHUNKS=$(( (SZ + 1023) / 1024 ))
: > /tmp/crash_pull.b64
for ((i=0; i<CHUNKS; i++)); do
    GOT=NO
    for try in $(seq 1 40); do
        B64=$(ssh_run "dd if=/tmp/crash.gz bs=1024 skip=$i count=1 2>/dev/null | base64" | grep -E '^[A-Za-z0-9+/=]+$' | tr -d '\r' | tr -d '\n')
        if [ -n "$B64" ]; then
            printf '%s' "$B64" >> /tmp/crash_pull.b64
            GOT=YES
            echo "$(date +%H:%M:%S) чанк $((i+1))/$CHUNKS"
            break
        fi
        sleep 6
    done
    [ "$GOT" = YES ] || { echo "чанк $((i+1)) не прошёл"; exit 1; }
done

base64 -D /tmp/crash_pull.b64 -o /tmp/crash_pull.gz 2>/dev/null || base64 -d /tmp/crash_pull.b64 > /tmp/crash_pull.gz
gunzip -f /tmp/crash_pull.gz && cp /tmp/crash_pull "crashlogs/$F" && echo "СОХРАНЕНО: crashlogs/$F ($(wc -c < "crashlogs/$F") байт)"
ssh_run "rm -f /tmp/crash.gz" >/dev/null 2>&1
