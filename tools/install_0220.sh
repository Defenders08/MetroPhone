#!/bin/bash
# Установка 0.22.0 на iPhone 4 по USB.
# Наблюдение: через один процесс iproxy надёжно проходит только ПЕРВОЕ соединение,
# следующие сбрасываются на kex_exchange_identification. Поэтому перед КАЖДЫМ
# подключением iproxy перезапускается целиком. Файл идёт одним соединением потоком
# через stdin (старый sshd iOS 6 не умеет sftp — scp из macOS по умолчанию отваливается).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PORT=2222
DEB="../builds/ru.ash.metrophone_0.22.0_iphoneos-arm.deb"
TOTAL_DEB=$(wc -c < "$DEB" | tr -d ' ')
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

# свежий туннель + до 3 попыток одного подключения; успех — по маркеру в выводе
ssh_step() {
    local marker="$1" cmd="$2" i
    for i in 1 2 3; do
        reconnect
        if run_ssh "$cmd" | grep -q "$marker"; then return 0; fi
        echo "  попытка $i не прошла, пересоздаю туннель"
        sleep 5
    done
    echo "FAIL: шаг не удался: $cmd"
    exit 1
}

echo "== 1/4: связь"
ssh_step "CLEANED" "rm -f /tmp/metrophone.deb; echo CLEANED"

echo "== 2/4: передача deb потоком через stdin ($TOTAL_DEB байт, одно соединение)"
reconnect
expect -c "
    set timeout 900
    spawn bash -c \"ssh $SSH_OPTS root@127.0.0.1 'cat > /tmp/metrophone.deb' < $DEB\"
    expect {
        -nocase {password:} { send \"alpine\r\"; exp_continue }
        eof
    }
" 2>/dev/null

echo "== 3/4: проверка размера и установка (dpkg сам проверит md5 внутри пакета)"
ssh_step "INSTALL_OK" "S=\$(wc -c < /tmp/metrophone.deb 2>/dev/null || echo 0); echo \"SIZE_\$S\"; if [ \"\$S\" -eq $TOTAL_DEB ]; then dpkg -i /tmp/metrophone.deb && echo INSTALL_OK; fi"

echo "== 4/4: respring"
ssh_step "RESPRUNG" "killall SpringBoard; echo RESPRUNG"
echo "== ГОТОВО: 0.22.0 установлена, SpringBoard перезапущен =="
