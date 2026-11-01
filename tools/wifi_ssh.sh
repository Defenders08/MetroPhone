#!/bin/bash
# SSH на iPhone 4 по Wi-Fi (без USB/iproxy).
# ВАЖНО: expect-блок только многострочный — однострочный «expect { ... }»
# парсер ломает: пароль не отправляется, сессия молча виснет до таймаута.
HOST=172.20.10.2
SSH_OPTS="-p 22 \
  -o HostkeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 \
  -o MACs=+hmac-sha1,hmac-sha1-96 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null"

run_ssh() {
    expect -c "
        set timeout 60
        spawn ssh $SSH_OPTS root@$HOST {$1}
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            eof
        }
    " 2>/dev/null
}

run_ssh "$@"
