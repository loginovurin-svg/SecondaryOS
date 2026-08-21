#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT/app/src/main/assets"
JNILIB_DIR="$ROOT/app/src/main/jniLibs/arm64-v8a"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

echo "=== SecondaryOS prepare_assets ==="

mkdir -p "$ASSETS_DIR" "$JNILIB_DIR"
rm -f "$ASSETS_DIR/proot_static" "$JNILIB_DIR/libproot.so" \
      "$ASSETS_DIR/debian-rootfs.tar.xz" "$ASSETS_DIR/busybox"

# 1. Proot
echo "=== Скачиваю proot ==="
curl -sS -fL --retry 3 -o "$WORK/proot" \
    "https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-aarch64-static"

cp "$WORK/proot" "$ASSETS_DIR/proot_static"
chmod 0755 "$ASSETS_DIR/proot_static"
cp "$WORK/proot" "$JNILIB_DIR/libproot.so"
chmod 0755 "$JNILIB_DIR/libproot.so"
echo "[OK] proot готов"

# 2. Busybox
echo "=== Устанавливаю кросс-компилятор ==="
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential bzip2 gcc-aarch64-linux-gnu

echo "=== Компилирую busybox для ARM64 ==="
cd "$WORK"

echo "Скачиваю исходники busybox..."
curl -sS -fL --retry 3 -o busybox.tar.bz2 \
    "https://busybox.net/downloads/busybox-1.36.1.tar.bz2"
tar xjf busybox.tar.bz2
cd busybox-1.36.1

# Создаём минимальную конфигурацию
echo "Создаю минимальную конфигурацию..."
make allnoconfig

# Включаем статическую линковку и базовые утилиты
cat >> .config << 'EOF'
CONFIG_STATIC=y
CONFIG_LS=y
CONFIG_CAT=y
CONFIG_ECHO=y
CONFIG_PWD=y
CONFIG_MKDIR=y
CONFIG_RM=y
CONFIG_CP=y
CONFIG_MV=y
CONFIG_SH_IS_ASH=y
CONFIG_ASH=y
CONFIG_ASH_JOB_CONTROL=y
CONFIG_ASH_ALIAS=y
CONFIG_ASH_BASH_COMPAT=y
CONFIG_HUSH=y
CONFIG_HUSH_INTERACTIVE=y
CONFIG_HUSH_JOB=y
CONFIG_HUSH_TICK=y
CONFIG_HUSH_IF=y
CONFIG_HUSH_LOOPS=y
CONFIG_HUSH_CASE=y
CONFIG_HUSH_FUNCTIONS=y
CONFIG_HUSH_LOCAL=y
CONFIG_HUSH_EXPORT=y
CONFIG_HUSH_KILL=y
CONFIG_HUSH_WAIT=y
CONFIG_HUSH_COMMAND=y
CONFIG_HUSH_TRAP=y
CONFIG_HUSH_TYPE=y
CONFIG_HUSH_READ=y
CONFIG_HUSH_SET=y
CONFIG_HUSH_UNSET=y
CONFIG_HUSH_ULIMIT=y
CONFIG_HUSH_UMASK=y
CONFIG_HUSH_GETOPTS=y
CONFIG_FEATURE_SH_MATH=y
CONFIG_FEATURE_SH_MATH_64=y
CONFIG_FEATURE_SH_MATH_BASE=y
CONFIG_FEATURE_SH_STANDALONE=y
CONFIG_FEATURE_SH_NOFORK=y
CONFIG_FEATURE_SH_EMBEDDED_SCRIPTS=y
CONFIG_FEATURE_SH_HISTFILESIZE=y
CONFIG_FEATURE_SH_READ_FRAC=y
CONFIG_FEATURE_SH_EXTRA_QUIET=y
CONFIG_FEATURE_FAST_TOP=y
CONFIG_FEATURE_SHOW_THREADS=y
CONFIG_FREE=y
CONFIG_KILL=y
CONFIG_KILLALL=y
CONFIG_PIDOF=y
CONFIG_PS=y
CONFIG_TOP=y
CONFIG_UPTIME=y
CONFIG_WATCH=y
CONFIG_TAR=y
CONFIG_GZIP=y
CONFIG_BUNZIP2=y
CONFIG_WGET=y
CONFIG_FEATURE_WGET_LONG_OPTIONS=y
CONFIG_FEATURE_WGET_STATUSBAR=y
CONFIG_FEATURE_WGET_HTTPS=y
CONFIG_CHMOD=y
CONFIG_CHOWN=y
CONFIG_DATE=y
CONFIG_DD=y
CONFIG_DF=y
CONFIG_DU=y
CONFIG_GREP=y
CONFIG_HEAD=y
CONFIG_ID=y
CONFIG_LINK=y
CONFIG_LN=y
CONFIG_MD5SUM=y
CONFIG_MKTEMP=y
CONFIG_MOUNT=y
CONFIG_UMOUNT=y
CONFIG_PRINTF=y
CONFIG_SED=y
CONFIG_SLEEP=y
CONFIG_SORT=y
CONFIG_TAIL=y
CONFIG_TOUCH=y
CONFIG_TR=y
CONFIG_UNAME=y
CONFIG_UNIQ=y
CONFIG_WC=y
CONFIG_XARGS=y
CONFIG_YES=y
CONFIG_FEATURE_PREFER_APPLETS=y
CONFIG_FEATURE_INSTALLER=y
CONFIG_BUSYBOX_EXEC_PATH="/proc/self/exe"
EOF

# Компилируем
echo "Компиляция (это займёт 2-5 минут)..."
make CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

if [ -f "busybox" ]; then
    cp busybox "$ASSETS_DIR/busybox"
    chmod 0755 "$ASSETS_DIR/busybox"
    echo "[OK] busybox скомпилирован (статический)"
else
    echo "[ERROR] не удалось скомпилировать busybox"
    exit 1
fi

# 3. Rootfs Debian 11
echo "=== Скачиваю Debian 11 rootfs ==="
ROOTFS_BASE_URL="https://images.linuxcontainers.org/images/debian/bullseye/arm64/default"

LATEST_DIR=$(curl -sS -fL "$ROOTFS_BASE_URL/" \
    | grep -oP '(?<=href=")[0-9]{8}_[0-9]{2}%3A[0-9]{2}' \
    | sort | tail -n 1)

if [[ -z "$LATEST_DIR" ]]; then
    echo "[ERROR] не найдена папка rootfs bullseye"
    exit 1
fi

ROOTFS_URL="$ROOTFS_BASE_URL/$LATEST_DIR/rootfs.tar.xz"
echo "Найдена сборка: $LATEST_DIR"

curl -sS -fL --retry 3 -o "$WORK/rootfs.tar.xz" "$ROOTFS_URL"
cp "$WORK/rootfs.tar.xz" "$ASSETS_DIR/debian-rootfs.tar.xz"

echo
echo "=== Файлы в assets ==="
ls -lh "$ASSETS_DIR"
echo
echo "=== Файлы в jniLibs ==="
ls -lh "$JNILIB_DIR"
echo
echo "=== prepare_assets.sh завершён успешно ==="
