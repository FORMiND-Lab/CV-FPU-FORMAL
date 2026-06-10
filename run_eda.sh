#!/bin/bash
set -e

if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

XAUTH=/tmp/.docker.xauth.$USER

rm -f "$XAUTH"
touch "$XAUTH"

if command -v xauth >/dev/null 2>&1; then
    xauth nlist "$DISPLAY" 2>/dev/null | \
        sed -e 's/^..../ffff/' | \
        xauth -f "$XAUTH" nmerge - 2>/dev/null || true
    chmod 600 "$XAUTH"
fi

# 临时允许 root 访问当前 X11
xhost +SI:localuser:root >/dev/null 2>&1 || true

# 脚本退出时自动撤销授权
cleanup() {
    xhost -SI:localuser:root >/dev/null 2>&1 || true
    rm -f "$XAUTH"
}
trap cleanup EXIT

# 使用 --net=host 时，2222 是宿主机网络命名空间的端口。
# 如果多个容器同时运行，请改成 2223/2224 等。
HECTOR_SSH_PORT="${HECTOR_SSH_PORT:-2222}"

docker run -it --rm \
    -u root \
    --net=host \
    -e DISPLAY="$DISPLAY" \
    -e XAUTHORITY="$XAUTH" \
    -e QT_X11_NO_MITSHM=1 \
    -e NO_AT_BRIDGE=1 \
    -e HECTOR_SSH_PORT="$HECTOR_SSH_PORT" \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "$XAUTH:$XAUTH:ro" \
    -v /home/synopsys:/eda/synopsys:ro \
    -v /home/cadence:/eda/cadence:ro \
    -v /home/synopsys/scl:/eda/scl:ro \
    -v /home/synopsys/eda_compat_libs:/opt/compat_libs:ro \
    -v "$PWD":/home/eda:rw \
    eda-base:rocky8.9 bash