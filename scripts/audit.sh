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

echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]