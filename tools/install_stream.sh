#!/bin/bash
# Потоковая установка deb на iPhone 4 по USB: файл целиком через stdin за одно
# соединение (старый sshd iOS 6 не умеет sftp). Перед КАЖДЫМ подключением iproxy
# перезапускается — через один процесс iproxy проходит только первое соединение.
#
# Отличие от install_0220.sh: маркеры успеха собираются конкатенацией строк
# (echo INSTALL"_OK"), чтобы grep не совпадал с ЭХОМ команды в выводе expect —
# из-за этого install_0220.sh мог «пройти» шаги, ничего не установив.
#
# Использование: ./install_stream.sh [путь/к/deb]   (по умолчанию новейший из builds/)

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PORT=2222
cd "$(dirname "$0")" || exit 1

DEB="$1"
if [ -z "$DEB" ]; then
    DEB=$(ls -t ../builds/ru.ash.metrophone_*_iphoneos-arm.deb 2>/dev/null | grep -v debug | head -1)
fi
[ -s "$DEB" ] || { echo "нет deb — сначала make package"; exit 1; }
TOTAL_DEB=$(wc -c < "$DEB" | tr -d ' ')
echo "ставлю: $DEB ($TOTAL_DEB байт)"

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
    sleep 4
}

run_ssh() {
    expect -c "
        set timeout 600
        spawn ssh $SSH_OPTS root@127.0.0.1 {$1}
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            eof
        }
    " 2>/dev/null
}

ssh_step() {
    local cmd="$1" i out
    for i in 1 2 3 4 5; do
        reconnect
        out=$(run_ssh "$cmd")
        if echo "$out" | grep -q "$2"; then return 0; fi
        echo "  попытка $i не прошла, пересоздаю туннель"
        sleep 5
    done
    echo "FAIL: шаг не удался: $cmd"
    exit 1
}

# ждём появления устройства по USB (до 10 минут)
echo "жду устройство по USB..."
for i in $(seq 1 60); do
    [ -n "$(idevice_id -l 2>/dev/null)" ] && break
    sleep 10
done
[ -n "$(idevice_id -l 2>/dev/null)" ] || { echo "USB-устройство так и не появилось"; exit 1; }

echo "== 1/4: связь"
ssh_step "rm -f /tmp/metrophone.deb; echo CLEAN" "CLEAN"

echo "== 2/4: передача deb потоком через stdin ($TOTAL_DEB байт)"
TRANS_OK=NO
for i in 1 2 3; do
    reconnect
    expect -c "
        set timeout 900
        spawn bash -c \"ssh $SSH_OPTS root@127.0.0.1 'cat > /tmp/metrophone.deb' < $DEB\"
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            eof
        }
    " 2>/dev/null
    # успех — только по фактическому размеру на телефоне (шаг 3), здесь до 3 попыток
    S=$(run_ssh "wc -c < /tmp/metrophone.deb 2>/dev/null" | grep -E '^[0-9]+$' | tail -1)
    if [ "$S" = "$TOTAL_DEB" ]; then TRANS_OK=YES; break; fi
    echo "  передача $i не доехала (на телефоне ${S:-0} из $TOTAL_DEB)"
done
[ "$TRANS_OK" = "YES" ] || { echo "FAIL: deb не доехал целиком"; exit 1; }

echo "== 3/4: установка"
ssh_step "dpkg -i /tmp/metrophone.deb && echo INSTALL"_OK" && dpkg -s ru.ash.metrophone | grep Version" "INSTALL_OK"

echo "== 4/4: respring"
ssh_step "killall SpringBoard; echo RESPRING"_DONE" "RESPRING_DONE"
echo "== ГОТОВО: $(basename "$DEB") установлена, SpringBoard перезапущен =="
