#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecondaryOS
# scripts/prepare_assets.sh — СБОРКА PROOT ЧЕРЕЗ WAF
#
# proot из ветки termux/proot требует свою систему сборки waf.
# Пытаться скомпилировать одним вызовом gcc не работает из-за
# встроенного loader и тестовых файлов.
# Rootfs: Debian 11 (bullseye).
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT/app/src/main/assets"
JNILIB_DIR="$ROOT/app/src/main/jniLibs/arm64-v8a"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

echo "=== SecondaryOS prepare_assets (waf build) ==="
echo "ROOT: $ROOT"

mkdir -p "$ASSETS_DIR" "$JNILIB_DIR"
rm -f "$ASSETS_DIR/proot_static" "$JNILIB_DIR/libproot.so" \
      "$ASSETS_DIR/debian-rootfs.tar.xz"

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

# ------------------------------------------------------------
# 1. Устанавливаем кросс-компилятор и waf
# ------------------------------------------------------------
echo "=== Устанавливаю gcc-aarch64-linux-gnu и python3 ==="
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq \
    gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
    python3 python3-pip

# waf можно взять из репозитория termux/proot (он там есть)
# или установить через pip, но проще скачать их waf-скрипт
echo "Проверка python3:"
python3 --version

# ------------------------------------------------------------
# 2. Скачиваем исходники proot из ветки Termux
# ------------------------------------------------------------
echo "=== Скачиваю proot (termux fork) ==="
curl -sS -fL --retry 3 -o "$WORK/proot.tar.gz" \
    "https://github.com/termux/proot/archive/refs/heads/master.tar.gz"

tar -xzf "$WORK/proot.tar.gz" -C "$WORK"
PROOT_DIR="$(echo "$WORK"/proot-*)"
echo "Исходники: $PROOT_DIR"

# ------------------------------------------------------------
# 3. Настраиваем и собираем через waf
# ------------------------------------------------------------
echo "=== Настраиваю proot через waf ==="
cd "$PROOT_DIR"

# Устанавливаем кросс-компилятор в переменные окружения
export CC="aarch64-linux-gnu-gcc"
export CXX="aarch64-linux-gnu-g++"
export AR="aarch64-linux-gnu-ar"
export STRIP="aarch64-linux-gnu-strip"

# waf configure с указанием целевой архитектуры
python3 waf configure \
    --target-arch=arm64 \
    --prefix=/usr \
    --static \
    --enable-seccomp \
    --enable-alloc-arena

echo "=== Собираю proot через waf ==="
python3 waf build

# ------------------------------------------------------------
# 4. Проверяем и копируем готовый бинарник
# ------------------------------------------------------------
PROOT_BIN="$PROOT_DIR/build/src/proot"

if [[ ! -f "$PROOT_BIN" ]]; then
    echo "ОШИБКА: waf не создал build/src/proot"
    ls -la "$PROOT_DIR/build/" || true
    exit 1
fi

echo "Проверка собранного proot:"
file "$PROOT_BIN" || true

if ! file "$PROOT_BIN" | grep -qi 'aarch64'; then
    echo "ОШИБКА: proot не aarch64"
    exit 1
fi
if ! file "$PROOT_BIN" | grep -qi 'statically linked'; then
    echo "ОШИБКА: proot не статический"
    exit 1
fi

# ------------------------------------------------------------
# 5. Кладём proot в assets и jniLibs
# ------------------------------------------------------------
cp "$PROOT_BIN" "$ASSETS_DIR/proot_static"
chmod 0755 "$ASSETS_DIR/proot_static"

cp "$PROOT_BIN" "$JNILIB_DIR/libproot.so"
chmod 0755 "$JNILIB_DIR/libproot.so"
echo "proot_static и libproot.so готовы"
echo

# ------------------------------------------------------------
# 6. Rootfs Debian 11 (bullseye)
# ------------------------------------------------------------
echo "=== Скачиваю Debian 11 rootfs ==="
ROOTFS_BASE_URL="https://images.linuxcontainers.org/images/debian/bullseye/arm64/default"

# Сервер кодирует двоеточие как %3A в HTML
LATEST_DIR=$(curl -sS -fL "$ROOTFS_BASE_URL/" \
    | grep -oP '(?<=href=")[0-9]{8}_[0-9]{2}%3A[0-9]{2}' \
    | sort | tail -n 1)

if [[ -z "$LATEST_DIR" ]]; then
    echo "ОШИБКА: не найдена папка rootfs bullseye"
    exit 1
fi

ROOTFS_URL="$ROOTFS_BASE_URL/$LATEST_DIR/rootfs.tar.xz"
echo "Найдена сборка: $LATEST_DIR"

curl -sS -fL --retry 3 -o "$WORK/rootfs.tar.xz" "$ROOTFS_URL"
cp "$WORK/rootfs.tar.xz" "$ASSETS_DIR/debian-rootfs.tar.xz"

echo
echo "Готовые assets:"
ls -lh "$ASSETS_DIR"
echo "Готовые jniLibs:"
ls -lh "$JNILIB_DIR"
echo "=== prepare_assets.sh завершён успешно ==="
