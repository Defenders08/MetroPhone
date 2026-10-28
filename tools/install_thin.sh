#!/bin/bash
# Передача тонкого deb на iPhone чанками base64 по 4 КБ через нестабильный SSH.
# Каждый чанк шлётся одной командой «дошли ли данные → если нет, допиши» и
# проверяется по счётчику байт на телефоне.
cd "$(dirname "$0")" || exit 1

CHUNK=1024
DEB=/tmp/mp_thin.deb
B64=/tmp/thin.b64
# нет /tmp/mp_thin.deb — берём новейший релизный deb из builds/
if [ ! -s "$DEB" ]; then
    NEWEST=$(ls -t ../builds/ru.ash.metrophone_*_iphoneos-arm.deb 2>/dev/null | grep -v debug | head -1)
    if [ -n "$NEWEST" ]; then
        cp "$NEWEST" "$DEB"
        echo "взял свежий деб: $NEWEST"
    fi
fi
# размер пакета считаем по факту — константа протухала с каждой версией
if [ ! -s "$DEB" ]; then
    echo "нет $DEB — сначала make package"
    exit 1
fi
TOTAL_DEB=$(wc -c < "$DEB" | tr -d ' ')

base64 -i "$DEB" -o "$B64"
rm -f /tmp/thc_
split -b $CHUNK "$B64" /tmp/thc_
CHUNKS=(/tmp/thc_*)
echo "чанков: ${#CHUNKS[@]}, base64: $(wc -c < "$B64") байт"

ssh_run() {
    ./iphone-ssh.sh "$1" 2>/dev/null
}

# ждём канал, способный нести хотя бы чанк: короткая проба каждые 20 с
echo "жду живой канал..."
PROBE=$(head -c 1024 "$B64")
LINK_OK=NO
DEADLINE=$((SECONDS + 5400))   # 2 часа на всё
while [ $SECONDS -lt $DEADLINE ]; do
    if [ -z "$(idevice_id -l 2>/dev/null)" ]; then sleep 15; continue; fi
    pkill -f "iproxy 2222" 2>/dev/null
    sleep 1
    nohup iproxy 2222:22 >/tmp/iproxy.log 2>&1 &
    disown
    sleep 3
    # printf вместо echo: echo добавляет перевод строки и wc давал 1025 вместо 1024 —
    # из-за этого проба никогда не проходила и скрипт ждал «канал» вечно
    R=$(ssh_run "printf '%s' '$PROBE' | wc -c" | grep -x "${#PROBE}" | head -1)
    if [ "$R" = "${#PROBE}" ]; then
        LINK_OK=YES
        echo "$(date +%H:%M:%S) канал жив (чанк проходит)"
        break
    fi
    sleep 15
done
if [ "$LINK_OK" != "YES" ]; then
    echo "за 2 часа канал так и не ожил"
    exit 1
fi

# очистка на телефоне
ssh_run "rm -f /tmp/mp.b64" >/dev/null 2>&1

offset=0
DEADLINE=$((SECONDS + 1500))
for f in "${CHUNKS[@]}"; do
    # $(cat ...) съедает хвостовой перевод строки чанка (чанк 77 и далее каждые 77) —
    # считаем размер по факту в переменной, иначе счётчик на телефоне не сойдётся
    DATA=$(cat "$f")
    CSIZE=${#DATA}
    TARGET=$((offset + CSIZE))
    SENT=NO
    while [ $SECONDS -lt $DEADLINE ]; do
        R=$(ssh_run "S=\$(wc -c < /tmp/mp.b64 2>/dev/null || echo 0); if [ \"\$S\" -eq $TARGET ]; then echo LANDED; elif [ \"\$S\" -lt $TARGET ]; then printf '%s' '$DATA' >> /tmp/mp.b64; fi; wc -c < /tmp/mp.b64 2>/dev/null || echo 0" | grep -E '^[0-9]+$' | tail -1)
        if [ "$R" = "$TARGET" ]; then
            SENT=YES
            break
        fi
        if [ -n "$R" ] && [ "$R" -gt "$TARGET" ]; then
            echo "ПЕРЕБОР на $f (на телефоне $R > $TARGET) — стартуем заново"
            ssh_run "rm -f /tmp/mp.b64" >/dev/null 2>&1
            offset=0
            break
        fi
        sleep 6
    done
    if [ "$SENT" != "YES" ]; then
        echo "ТАЙМАУТ на чанке $f"
        exit 1
    fi
    offset=$TARGET
    echo "$(date +%H:%M:%S) $f → $offset / $(wc -c < "$B64")"
done

echo "=== base64 доставлен, декодируем и ставим ==="
OUT=$(ssh_run "base64 -D -i /tmp/mp.b64 -o /tmp/mp.deb 2>/dev/null || base64 -d /tmp/mp.b64 > /tmp/mp.deb; ls -l /tmp/mp.deb | awk '{print \$5}'" | grep -E '^[0-9]+$' | tail -1)
echo "на телефоне: $OUT байт (ожидалось $TOTAL_DEB)"
if [ "$OUT" != "$TOTAL_DEB" ]; then
    echo "РАЗМЕР НЕ СОВПАЛ — отмена"
    exit 1
fi
ssh_run "dpkg -i /tmp/mp.deb 2>&1; rm -f /tmp/mp.deb /tmp/mp.b64; dpkg -s ru.ash.metrophone | grep Version" | tail -4
echo "=== RESPRING ==="
ssh_run "killall SpringBoard" >/dev/null 2>&1
sleep 18
ssh_run "launchctl list | grep SpringBoard; tail -4 /var/mobile/Library/Preferences/metrophone.log" | tail -6
echo "=== ГОТОВО ==="
