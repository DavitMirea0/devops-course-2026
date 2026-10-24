#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "[OK] $desc"
        ((PASS+=1))
    else
        echo "[FAIL] $desc: expected=$expected actual=$actual"
        ((FAIL+=1))
    fi
}

sudo -v || exit 1
CFG=$(sudo sshd -T) || exit 1

get() {
    awk -v key="$1" '$1 == key {print $2}' <<< "$CFG"
}

check "Root login disabled" no "$(get permitrootlogin)"
check "Password authentication disabled" no "$(get passwordauthentication)"

PORTS=$(get port)
if [[ -n "$PORTS" ]] && ! grep -qx 22 <<< "$PORTS"; then
    check "SSH port differs from 22" yes yes
else
    check "SSH port differs from 22" yes no
fi

check "MaxAuthTries equals 3" 3 "$(get maxauthtries)"

UFW=$(sudo ufw status verbose) || exit 1
check "UFW active" active "$(awk '/^Status:/ {print $2}' <<< "$UFW")"

POLICY=$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$UFW")
check "Incoming policy is deny" deny "$POLICY"

echo "User accounts:"
awk -F: '$3>=1000 && $3<65534 {print $1, $3}' /etc/passwd

# Проверки контейнеризации
check "Docker service active" active "$(systemctl is-active docker 2>/dev/null || true)"

DB_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || true)
check "PostgreSQL container healthy" healthy "$DB_HEALTH"

APP_PORT=$(docker port app-app-1 5000/tcp 2>/dev/null || true)
DB_PORT=$(docker port app-db-1 5432/tcp 2>/dev/null || true)
if [[ "$APP_PORT" == "127.0.0.1:5000" && -z "$DB_PORT" ]]; then
    check "App is loopback-only; DB port is unpublished" yes yes
else
    check "App is loopback-only; DB port is unpublished" yes "app=$APP_PORT db=$DB_PORT"
fi

ENV_MODE=$(stat -c '%a' /home/devops/app/.env 2>/dev/null || true)
check ".env permissions are 600" 600 "$ENV_MODE"

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]