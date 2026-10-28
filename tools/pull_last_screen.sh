#!/bin/bash
# Тянуть /tmp/scr.b64 (base64 последнего скрина, уже подготовлен на телефоне)
# блоками по 32 КБ с точной проверкой длины каждого; перед каждым соединением —
# свежий iproxy. Собранный файл декодируется, проверяется gunzip -t, PNG в archive.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
CHUNK=32768
TOTAL=341451                    # размер /tmp/scr.b64 (проверяется на телефоне при старте)
OUT=/tmp/scr203.b64
DEST="/Users/ash/Documents/Проекты/MetroPhone/archive/screens/last_screen.png"
SSH_OPTS="-p 2222 \
  -o HostkeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 \
  -o MACs=+hmac-sha1,hmac-sha1-96 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null"

expect_ssh() {
    expect -c "
        set timeout 120
        spawn ssh $SSH_OPTS root@127.0.0.1 {$1}
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            timeout { puts \"__TIMEOUT__\" }
            eof
        }
    " 2>/dev/null
}

conn() {
    local i out
    for i in 1 2 3 4 5 6; do
        if [ -z "$(idevice_id -l 2>/dev/null)" ]; then sleep 8; continue; fi
        pkill -f "iproxy 2222" 2>/dev/null
        sleep 1
        nohup iproxy 2222:22 >/tmp/iproxy.log 2>&1 &
        disown
        sleep 4
        out=$(expect_ssh "$1")
        if [ -n "$out" ] && ! echo "$out" | grep -q "__TIMEOUT__"; then
            echo "$out"
            return 0
        fi
        sleep 5
    done
    return 1
}

DEADLINE=$((SECONDS + 1800))    # 30 минут на всё
: > "$OUT"
while [ $SECONDS -lt $DEADLINE ]; do
    HAVE=$(wc -c < "$OUT" | tr -d ' ')
    # проверяем, что на телефоне тот же файл (на случай пересоздания скрина юзером)
    R=$(conn "wc -c < /tmp/scr.b64 2>/dev/null | tr -d ' '" | grep -E '^[0-9]+$' | tail -1)
    [ -n "$R" ] || { echo "$(date +%H:%M:%S) связи нет, ждём"; sleep 10; continue; }
    if [ "$R" != "$TOTAL" ]; then
        echo "на телефоне /tmp/scr.b64 = $R (ожидался $TOTAL) — переготавливаю"
        conn "F=\$(ls -t /var/mobile/Media/DCIM/100APPLE | head -1); echo FILE_\$F; gzip -9 -c \"/var/mobile/Media/DCIM/100APPLE/\$F\" > /tmp/scr.gz; base64 /tmp/scr.gz > /tmp/scr.b64; wc -c < /tmp/scr.b64 | tr -d ' '" | grep -E '^[0-9]+$' | tail -1
        : > "$OUT"   # файл на телефоне сменился — накопленное невалидно
        sleep 5
        continue
    fi
    if [ "$HAVE" -ge "$TOTAL" ]; then break; fi

    BLOCK=$(( HAVE / CHUNK ))
    REM=$(( TOTAL - HAVE ))
    WANT=$(( REM < CHUNK ? REM : CHUNK ))
    # двойное base64: блок ещё раз кодируется в base64 для транспорта
    EXPECT_B64=$(( 4 * ( (WANT + 2) / 3 ) ))
    GOT=$(conn "dd if=/tmp/scr.b64 bs=$CHUNK skip=$BLOCK count=1 2>/dev/null | base64" | grep -E '^[A-Za-z0-9+/=]+$' | tr -d '\r\n')
    GLEN=${#GOT}
    if [ "$GLEN" -eq "$EXPECT_B64" ]; then
        printf '%s' "$GOT" | base64 -d >> "$OUT" 2>/dev/null
        echo "$(date +%H:%M:%S) блок $BLOCK ок: $(wc -c < "$OUT" | tr -d ' ')/$TOTAL"
    else
        echo "$(date +%H:%M:%S) блок $BLOCK мимо ($GLEN из $EXPECT_B64)"
        sleep 6
    fi
done

HAVE=$(wc -c < "$OUT" | tr -d ' ')
if [ "$HAVE" != "$TOTAL" ]; then echo "FAIL: собрано $HAVE из $TOTAL"; exit 1; fi
base64 -d "$OUT" > /tmp/scr203.gz 2>/dev/null
gunzip -t /tmp/scr203.gz || { echo "FAIL: gzip битый"; exit 1; }
gunzip -c /tmp/scr203.gz > "$DEST"
file "$DEST" && du -h "$DEST"
conn "rm -f /tmp/scr.gz /tmp/scr.b64" >/dev/null
echo "=== ГОТОВО: $DEST ==="
