#!/bin/bash
# Установка deb на iPhone 4 по Wi-Fi. Многострочный expect (однострочный
# парсер ломает — пароль не уходит). Маркеры через конкатенацию, чтобы grep
# не совпал с эхом команды в выводе expect.
#
# Использование: ./wifi_install.sh /путь/к/deb

HOST=172.20.10.2
DEB="$1"
[ -s "$DEB" ] || { echo "нет deb: $DEB"; exit 1; }
TOTAL_DEB=$(wc -c < "$DEB" | tr -d ' ')
echo "ставлю: $(basename "$DEB") ($TOTAL_DEB байт)"

SSH_OPTS="-p 22 \
  -o HostkeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 \
  -o MACs=+hmac-sha1,hmac-sha1-96 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null"

run_ssh() {
    expect -c "
        set timeout 600
        spawn ssh $SSH_OPTS root@$HOST {$1}
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            eof
        }
    " 2>/dev/null
}

ssh_step() {  # $1 = маркер успеха, $2 = команда
    local marker="$1" cmd="$2" i out
    for i in 1 2 3 4 5; do
        out=$(run_ssh "$cmd" | tr -d '\r')
        if echo "$out" | grep -q "$marker"; then return 0; fi
        echo "  попытка $i не прошла, повтор через 8 с"
        sleep 8
    done
    echo "FAIL: $cmd"
    return 1
}

echo "== 1/4: очистка"
ssh_step "CLEANED" "rm -f /tmp/metrophone.deb; echo CLEANED" || exit 1

echo "== 2/4: передача deb потоком ($TOTAL_DEB байт)"
TRANS_OK=NO
for i in 1 2 3; do
    expect -c "
        set timeout 900
        spawn bash -c \"ssh $SSH_OPTS root@$HOST 'cat > /tmp/metrophone.deb' < $DEB\"
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            eof
        }
    " 2>/dev/null
    GOT=$(run_ssh "wc -c < /tmp/metrophone.deb" | tr -d '\r' | grep -x '[0-9][0-9]*' | tail -1)
    echo "  на телефоне: ${GOT:-нет} байт"
    if [ "$GOT" = "$TOTAL_DEB" ]; then TRANS_OK=YES; break; fi
done
[ "$TRANS_OK" = "YES" ] || { echo "FAIL: размер не сошёлся"; exit 1; }

echo "== 3/4: dpkg -i"
ssh_step "INSTALL_OK" "S=0; S=\$(wc -c < /tmp/metrophone.deb); if [ \"\$S\" -eq $TOTAL_DEB ]; then dpkg -i /tmp/metrophone.deb && rm -f /tmp/metrophone.deb && echo INSTALL\"\"_OK; fi" || exit 1

echo "== 4/4: respring"
ssh_step "RESPRUNG" "killall SpringBoard; echo RESPR\"\"UNG" || exit 1

echo "ГОТОВО: $(basename "$DEB") установлен, SpringBoard перезапущен"
