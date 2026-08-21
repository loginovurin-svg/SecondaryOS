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

# Создаём базовую конфигурацию с значениями по умолчанию
echo "Создаю базовую конфигурацию..."
make defconfig < /dev/null

# Включаем статическую линковку (ВАЖНО для Android!)
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Отключаем tc (traffic control), так как в новых ядрах Linux заголовки CBQ удалены, 
# что вызывает ошибку компиляции networking/tc.c
sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config

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
