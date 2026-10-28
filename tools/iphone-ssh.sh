#!/bin/bash
# Подключение к iPhone 4 (iPhone3,1, iOS 6.1.3, джейлбрейк, OpenSSH) по SSH.
# Связь идёт через USB (usbmuxd + iproxy), пароль — стандартный alpine.
# Использование:
#   ./iphone-ssh.sh "uname -a; df -h /"   — выполнить команду на телефоне
#   ./iphone-ssh.sh                        — интерактивная root-сессия

PORT=2222
# Homebrew-утилиты (iproxy, idevice_id) лежат в /opt/homebrew/bin: без этого PATH
# скрипт падает с «не удалось поднять iproxy», хотя телефон подключён.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
SSH_OPTS="-p $PORT \
  -o HostkeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 \
  -o MACs=+hmac-sha1,hmac-sha1-96 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null"

# Старый sshd на iOS 6 не понимает современные алгоритмы macOS, поэтому
# соединение оборачиваем в expect (пароль вводится неинтерактивно).
run_ssh() {
    local target="root@127.0.0.1"
    if [ $# -gt 0 ]; then
        expect -c "
            set timeout 60
            spawn ssh $SSH_OPTS $target {$*}
            expect {
                -nocase {password:} { send \"alpine\r\"; exp_continue }
                eof
            }
        "
    else
        expect -c "
            set timeout -1
            spawn ssh $SSH_OPTS $target
            expect {
                -nocase {password:} { send \"alpine\r\"; exp_continue }
                eof
            }
        "
    fi
}

# Поднимаем USB-туннель, если он ещё не работает
if ! nc -z 127.0.0.1 $PORT 2>/dev/null; then
    pkill -f "iproxy $PORT" 2>/dev/null
    nohup iproxy $PORT:22 >/tmp/iproxy.log 2>&1 &
    sleep 2
    if ! nc -z 127.0.0.1 $PORT 2>/dev/null; then
        echo "Ошибка: не удалось поднять iproxy — проверь, что телефон подключён по USB" >&2
        exit 1
    fi
fi

# ./iphone-ssh.sh --push файл /tmp/путь — передать файл по scp (например, .deb с твиком)
if [ "$1" = "--push" ]; then
    # у scp флаг порта -P, а не -p как у ssh
    expect -c "
        set timeout 120
        spawn scp ${SSH_OPTS/-p $PORT/-P $PORT} $2 root@127.0.0.1:$3
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            eof
        }
    "
    exit $?
fi

# ./iphone-ssh.sh --pull /путь/на/телефоне локальный_файл — забрать файл по scp
if [ "$1" = "--pull" ]; then
    expect -c "
        set timeout 120
        spawn scp ${SSH_OPTS/-p $PORT/-P $PORT} root@127.0.0.1:$2 $3
        expect {
            -nocase {password:} { send \"alpine\r\"; exp_continue }
            eof
        }
    "
    exit $?
fi

run_ssh "$@"
