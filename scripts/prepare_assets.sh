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
      "$ASSETS_DIR/debian-rootfs.tar.xz" "$ASSETS_DIR/toybox"

# 1. Proot
echo "=== Скачиваю proot ==="
curl -sS -fL --retry 3 -o "$WORK/proot" \
    "https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-aarch64-static"

cp "$WORK/proot" "$ASSETS_DIR/proot_static"
chmod 0755 "$ASSETS_DIR/proot_static"
cp "$WORK/proot" "$JNILIB_DIR/libproot.so"
chmod 0755 "$JNILIB_DIR/libproot.so"
echo "[OK] proot готов"

# 2. Toybox с musl libc
echo "=== Устанавливаю кросс-компилятор и musl ==="
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential gcc-aarch64-linux-gnu

echo "=== Компилирую toybox с musl для ARM64 ==="
cd "$WORK"

# Скачиваем musl libc
echo "Скачиваю musl libc..."
curl -sS -fL --retry 3 -o musl.tar.gz \
    "https://musl.libc.org/releases/musl-1.2.4.tar.gz"
tar xzf musl.tar.gz
cd musl-1.2.4

# Компилируем musl для ARM64
echo "Компилирую musl..."
./configure --prefix=/opt/musl-aarch64 --target=aarch64-linux-gnu
make -j$(nproc)
sudo make install

# Возвращаемся в рабочую папку
cd "$WORK"

echo "Скачиваю исходники toybox..."
curl -sS -fL --retry 3 -o toybox.tar.gz \
    "https://github.com/landley/toybox/archive/refs/tags/0.8.9.tar.gz"
tar xzf toybox.tar.gz
cd toybox-0.8.9

echo "Создаю конфигурацию toybox..."
make defconfig

# Статическая линковка
sed -i 's/# CONFIG_TOYBOX_STATIC is not set/CONFIG_TOYBOX_STATIC=y/' .config

# Отключаем утилиты, требующие libcrypt
sed -i 's/CONFIG_PASSWD=y/# CONFIG_PASSWD is not set/' .config
sed -i 's/CONFIG_SU=y/# CONFIG_SU is not set/' .config
sed -i 's/CONFIG_LOGIN=y/# CONFIG_LOGIN is not set/' .config
sed -i 's/CONFIG_MKPASSWD=y/# CONFIG_MKPASSWD is not set/' .config

# Компилируем toybox с musl-gcc напрямую
echo "Компиляция toybox с musl (2-5 минут)..."
export CC="/opt/musl-aarch64/bin/musl-gcc"
export CFLAGS="-static -I/opt/musl-aarch64/include"
export LDFLAGS="-L/opt/musl-aarch64/lib"

make -j$(nproc)

if [ -f "toybox" ]; then
    # Проверяем, что бинарник статический
    if file toybox | grep -q "statically linked"; then
        cp toybox "$ASSETS_DIR/toybox"
        chmod 0755 "$ASSETS_DIR/toybox"
        echo "[OK] toybox скомпилирован (статический с musl)"
    else
        echo "[ERROR] toybox не статический!"
        file toybox
        exit 1
    fi
else
    echo "[ERROR] не удалось скомпилировать toybox"
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
echo "=== prepare_assets.sh завершён ==="
