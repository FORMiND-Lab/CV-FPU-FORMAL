#!/usr/bin/env bash
set -euo pipefail

WORKERS="${1:-4}"
RUN_DIR="${HECTOR_RUN_DIR:-/home/eda/formal/run}"

start-hector-ssh.sh

mkdir -p /tmp/hector_qsub
chmod 777 /tmp/hector_qsub

if [ ! -d "${RUN_DIR}" ]; then
    echo "[WARN] Hector run dir not found: ${RUN_DIR}"
    echo "[WARN] Skip writing host.qsub. You can run this later after mounting your project."
    exit 0
fi

cd "${RUN_DIR}"

cat > host.qsub <<EOF
1 | localhost | ${WORKERS} | /tmp/hector_qsub | SSH | ssh
EOF

echo "[OK] host.qsub generated:"
cat host.qsub