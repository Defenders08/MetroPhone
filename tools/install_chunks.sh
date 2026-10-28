#!/bin/bash
# Чанковая установка deb на iPhone 4 для ПЛОХОГО канала (когда поток 5 МБ рвётся).
# Отличия от install_thin.sh:
#  - каждый чанк — ОТДЕЛЬНЫЙ файл /tmp/mp_c/NNNNNN на телефоне: недолетевший чанк
#    перепосылается сам, готовые не пересылаются, «сброса с нуля» нет;
#  - адаптивный размер чанка: если подряд 3 чанка не легли, размер делится (32К→8К→2К);
#  - маркеры без самопересечения с эхом expect (см. install_stream.sh).
# Использование: ./install_chunks.sh [деб]
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PORT=2222
cd "$(dirname "$0")" || exit 1

DEB="$1"
if [ -z "$DEB" ]; then
    DEB=$(ls -t ../builds/ru.ash.metrophone_*_iphoneos-arm.deb 2>/dev/null | grep -v debug | head -1)
fi
[ -s "$DEB" ] || { echo "нет deb"; exit 1; }
TOTAL_DEB=$(wc -c < "$DEB" | tr -d ' ')
echo "ставлю: $(basename "$DEB") ($TOTAL_DEB байт)"

SSH_OPTS="-p $PORT \
  -o HostkeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 \
  -o MACs=+hmac-sha1,hmac-sha1-96 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null"

reconnect() {
    pkill -f "iproxy $PORT" 2>/dev/null
    sleep 1
    nohup iproxy $PORT:22 >/tmp/iproxy.log 2>&1 &
    disown
    sleep 3
}

run_ssh() {
    expect -c "
        set timeout 120
        spawn ssh $SSH_OPTS root@127.0.0.1 {$1}
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            eof
        }
    " 2>/dev/null
}

# ждём USB (до 10 мин)
for i in $(seq 1 60); do
    [ -n "$(idevice_id -l 2>/dev/null)" ] && break
    sleep 10
done
[ -n "$(idevice_id -l 2>/dev/null)" ] || { echo "USB-устройства нет"; exit 1; }

reconnect
run_ssh "rm -rf /tmp/mp_c; mkdir -p /tmp/mp_c; echo READY" >/dev/null 2>&1

base64 -i "$DEB" -o /tmp/mp_c.b64
SIZE_B64=$(wc -c < /tmp/mp_c.b64 | tr -d ' ')
CHUNK=32768
NCHUNKS=$(( (SIZE_B64 + CHUNK - 1) / CHUNK ))
echo "b64: $SIZE_B64 байт, чанков: $NCHUNKS (по $CHUNK)"

split -a 5 -b $CHUNK /tmp/mp_c.b64 /tmp/mpchunk_
DEADLINE=$((SECONDS + 7200))   # 2 часа
fails=0
sent=0
i=0
for f in /tmp/mpchunk_*; do
    [ $SECONDS -gt $DEADLINE ] && { echo "ТАЙМАУТ"; exit 1; }
    i=$((i+1))
    [ -s "$f" ] || continue
    [ -f "$f.done" ] && continue
    DATA=$(cat "$f")
    # до 2 попыток чанка, затем пересоздать туннель и продолжить со следующего прохода
    for try in 1 2; do
        R=$(run_ssh "printf '%s' '$DATA' > /tmp/mp_c/$(basename "$f"); wc -c < /tmp/mp_c/$(basename "$f")" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
        if [ "$R" = "${#DATA}" ]; then
            touch "$f.done"; sent=$((sent+1)); fails=0
            break
        fi
        fails=$((fails+1))
        [ $fails -ge 3 ] && [ $CHUNK -gt 2048 ] && {
            CHUNK=$((CHUNK / 4)); fails=0
            echo "$(date +%H:%M:%S) канал плох — режу чанк до $CHUNK"
            rm -f /tmp/mpchunk_*
            split -a 5 -b $CHUNK /tmp/mp_c.b64 /tmp/mpchunk_
            # перенести метки готовности нельзя (чанки другие) — начинаем новую сетку
            NCHUNKS=$(( (SIZE_B64 + CHUNK - 1) / CHUNK ))
            i=0; sent=0
        }
        reconnect
        sleep 2
    done
    [ $((i % 25)) -eq 0 ] && echo "$(date +%H:%M:%S) чанк $i/$NCHUNKS"
done
echo "передано $sent/$NCHUNKS чанков"

echo "== склейка и установка =="
reconnect
OUT=$(run_ssh "cat /tmp/mp_c/* > /tmp/mp.b64; ls /tmp/mp_c | wc -l" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
OUT=$(run_ssh "base64 -D -i /tmp/mp.b64 -o /tmp/metrophone.deb 2>/dev/null || base64 -d /tmp/mp.b64 > /tmp/metrophone.deb; wc -c < /tmp/metrophone.deb" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)
echo "на телефоне: ${OUT:-0} байт (ожидалось $TOTAL_DEB)"
if [ "$OUT" != "$TOTAL_DEB" ]; then echo "РАЗМЕР НЕ СОВПАЛ"; exit 1; fi
run_ssh "dpkg -i /tmp/metrophone.deb && echo INSTALL"_OK" && dpkg -s ru.ash.metrophone | grep Version; rm -rf /tmp/mp_c /tmp/mp.b64 /tmp/metrophone.deb" 2>/dev/null | grep -vE '^(spawn |Warning:|root@)' | tail -3
echo "== respring =="
run_ssh "killall SpringBoard; echo RESPRING"_DONE"" >/dev/null 2>&1
sleep 20
run_ssh "launchctl list | grep SpringBoard; tail -3 /var/mobile/Library/Preferences/metrophone.log" 2>/dev/null | grep -vE '^(spawn |Warning:|root@)' | tail -4
echo "== ГОТОВО =="
