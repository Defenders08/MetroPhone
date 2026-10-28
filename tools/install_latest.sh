#!/bin/bash
# Универсальный установщик: новейший релизный deb из builds/ → iPhone 4.
# Канал плавает: перед КАЖДЫМ подключением iproxy пересоздаётся (живёт только
# первое соединение), файл идёт одним соединением потоком через stdin
# (sftp на iOS 6 нет, scp из macOS = sftp).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PORT=2222
DEB=$(ls -t ../builds/ru.ash.metrophone_*_iphoneos-arm.deb 2>/dev/null | grep -v debug | head -1)
[ -n "$DEB" ] || { echo "нет deb в ../builds/"; exit 1; }
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

ssh_step() {  # $1 = маркер успеха, $2 = команда
    local marker="$1" cmd="$2" i
    for i in 1 2 3 4 5; do
        [ -z "$(idevice_id -l 2>/dev/null)" ] && { sleep 8; continue; }
        reconnect
        if run_ssh "$cmd" | grep -q "$marker"; then return 0; fi
        echo "  попытка $i не прошла"
        sleep 5
    done
    echo "FAIL: $cmd"
    return 1
}

ssh_step "CLEANED" "rm -f /tmp/metrophone.deb; echo CLEANED" || exit 1

echo "== передача deb потоком через stdin (одно соединение) =="
reconnect
expect -c "
    set timeout 900
    spawn bash -c \"ssh $SSH_OPTS root@127.0.0.1 'cat > /tmp/metrophone.deb' < $DEB\"
    expect {
        -nocase {password:} { send \"alpine\r\"; exp_continue }
        eof
    }
" 2>/dev/null

ssh_step "INSTALL_OK" "S=\$(wc -c < /tmp/metrophone.deb 2>/dev/null || echo 0); echo \"SIZE_\$S\"; if [ \"\$S\" -eq $TOTAL_DEB ]; then dpkg -i /tmp/metrophone.deb && rm -f /tmp/metrophone.deb && echo INSTALL_OK; fi" || exit 1

ssh_step "RESPRUNG" "killall SpringBoard; echo RESPRUNG"
echo "== ГОТОВО: $(basename "$DEB") установлен, SpringBoard перезапущен =="
