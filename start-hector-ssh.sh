#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] start-hector-ssh.sh must run as root."
    echo "        Your docker run script already uses -u root, so this should be OK."
    exit 1
fi

PORT="${1:-${HECTOR_SSH_PORT:-2222}}"
LOG="/tmp/sshd_${PORT}.log"

echo "[INFO] Starting Hector SSH localhost worker on port ${PORT}"

mkdir -p /run/sshd

# Generate SSH host keys if missing
ssh-keygen -A

# Generate root login key for localhost worker
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f /root/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
fi

cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys

# SSH client config.
# host.qsub 中只能写 `SSH | ssh`，所以端口、私钥、BatchMode 参数都放这里。
cat > /root/.ssh/config <<EOF
Host localhost
    HostName localhost
    Port ${PORT}
    User root
    IdentityFile /root/.ssh/id_ed25519
    IdentitiesOnly yes
    BatchMode yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

chmod 600 /root/.ssh/id_ed25519
chmod 644 /root/.ssh/id_ed25519.pub
chmod 600 /root/.ssh/authorized_keys
chmod 600 /root/.ssh/config
chown -R root:root /root/.ssh

# Stop old Hector sshd on this port if any.
# 注意：不要 pkill 所有 sshd，避免影响其他用途。
pkill -f "sshd.*-p ${PORT}" 2>/dev/null || true

# Start sshd on dedicated port.
nohup /usr/sbin/sshd -D -e -p "${PORT}" > "${LOG}" 2>&1 &

sleep 1

if ! grep -q "Server listening" "${LOG}"; then
    echo "[ERROR] sshd did not start correctly on port ${PORT}"
    cat "${LOG}" || true
    exit 1
fi

# Verify localhost login.
if ! ssh localhost hostname >/tmp/hector_ssh_test.log 2>&1; then
    echo "[ERROR] ssh localhost test failed"
    echo "===== ${LOG} ====="
    cat "${LOG}" || true
    echo "===== /tmp/hector_ssh_test.log ====="
    cat /tmp/hector_ssh_test.log || true
    exit 1
fi

echo "[OK] Hector SSH localhost worker is ready on port ${PORT}"