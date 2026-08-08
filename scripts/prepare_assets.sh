#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecondaryOS
# scripts/prepare_assets.sh
#
# proot собирается кросс-компилятором из репозитория Ubuntu
# (gcc-aarch64-linux-gnu), статически, из исходников ветки
# Termux (там патчи для Android, включая обход seccomp/rseq).
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT/app/src/main/assets"
JNILIB_DIR="$ROOT/app/src/main/jniLibs/arm64-v8a"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

echo "=== SecondaryOS prepare_assets ==="
echo "ROOT: $ROOT"
echo "WORK: $WORK"

mkdir -p "$ASSETS_DIR" "$JNILIB_DIR"
rm -f "$ASSETS_DIR/proot_static" "$JNILIB_DIR/libproot.so"

# sudo нужен только если мы не root и sudo существует
SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

# ------------------------------------------------------------
# 1. Кросс-компилятор aarch64 из репозитория Ubuntu
# ------------------------------------------------------------
echo "=== Устанавливаю gcc-aarch64-linux-gnu ==="
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq gcc-aarch64-linux-gnu libc6-dev-arm64-cross

CC="aarch64-linux-gnu-gcc"
echo "Компилятор: $CC"
"$CC" --version | head -n 1

# ------------------------------------------------------------
# 2. Скачиваем и компилируем talloc (один .c файл)
# ------------------------------------------------------------
echo "=== Скачиваю talloc ==="

download_with_fallback() {
    local out="$1"
    shift
    local url
    for url in "$@"; do
        echo "Пробую: $url"
        if curl -sS -fL --retry 2 --connect-timeout 30 -o "$out" "$url"; then
            echo "Скачано: $out"
            return 0
        fi
    done
    echo "ОШИБКА: не удалось скачать $out ни с одного зеркала"
    return 1
}

download_with_fallback "$WORK/talloc.tar.gz" \
    "https://www.samba.org/ftp/talloc/talloc-2.4.2.tar.gz" \
    "https://ftp.samba.org/pub/talloc/talloc-2.4.2.tar.gz"

tar -xzf "$WORK/talloc.tar.gz" -C "$WORK"
TALLOC_DIR="$WORK/talloc-2.4.2"

echo "=== Компилирую talloc ==="
"$CC" -c "$TALLOC_DIR/talloc.c" \
    -I "$TALLOC_DIR" \
    -D_GNU_SOURCE -O2 \
    -o "$WORK/talloc.o"
echo "talloc.o готов"

# ------------------------------------------------------------
# 3. Исходники proot из ветки Termux
# ------------------------------------------------------------
echo "=== Скачиваю proot (termux fork) ==="
download_with_fallback "$WORK/proot.tar.gz" \
    "https://github.com/termux/proot/archive/refs/heads/master.tar.gz" \
    "https://codeload.github.com/termux/proot/tar.gz/refs/heads/master"

tar -xzf "$WORK/proot.tar.gz" -C "$WORK"
PROOT_SRC="$(echo "$WORK"/proot-*/src)"
echo "Исходники: $PROOT_SRC"

# ------------------------------------------------------------
# 4. Компилируем proot статически
# ------------------------------------------------------------
echo "=== Компилирую proot ==="
cd "$PROOT_SRC"

SRCS=$(find . -name '*.c' | sort)
echo "Файлов для компиляции: $(echo "$SRCS" | wc -l)"

"$CC" -O2 -static \
    -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 \
    -I. -I "$TALLOC_DIR" \
    $SRCS "$WORK/talloc.o" \
    -o "$WORK/proot"

echo "Проверка собранного proot:"
file "$WORK/proot" || true

if ! file "$WORK/proot" | grep -qi 'aarch64'; then
    echo "ОШИБКА: proot не aarch64"
    exit 1
fi

if ! file "$WORK/proot" | grep -qi 'statically linked'; then
    echo "ОШИБКА: proot не статический"
    exit 1
fi

# ------------------------------------------------------------
# 5. Кладём proot в assets и jniLibs
# ------------------------------------------------------------
cp "$WORK/proot" "$ASSETS_DIR/proot_static"
chmod 0755 "$ASSETS_DIR/proot_static"

cp "$WORK/proot" "$JNILIB_DIR/libproot.so"
chmod 0755 "$JNILIB_DIR/libproot.so"
echo "proot_static и libproot.so готовы"
echo

# ------------------------------------------------------------
# 6. Debian rootfs (images.linuxcontainers.org)
# ------------------------------------------------------------
echo "=== Получение Debian rootfs ==="
ROOTFS_URL="${ROOTFS_URL:-}"

if [[ -z "$ROOTFS_URL" ]]; then
    ROOTFS_BASE_URL="https://images.linuxcontainers.org/images/debian/bookworm/arm64/default"
    LATEST_DIR=$(curl -sS -fL "$ROOTFS_BASE_URL/" | grep -oP '(?<=href=")[0-9]{8}_[0-9]{2}%3A[0-9]{2}' | sort | tail -n 1)
    if [[ -z "$LATEST_DIR" ]]; then
        echo "ОШИБКА: не найдена папка rootfs"
        exit 1
    fi
    ROOTFS_URL="$ROOTFS_BASE_URL/$LATEST_DIR/rootfs.tar.xz"
    echo "Найдена сборка: $LATEST_DIR"
fi

curl -sS -fL --retry 3 -o "$WORK/rootfs.tar.xz" "$ROOTFS_URL"
cp "$WORK/rootfs.tar.xz" "$ASSETS_DIR/debian-rootfs.tar.xz"

echo
echo "Готовые assets:"
ls -lh "$ASSETS_DIR"
echo "Готовые jniLibs:"
ls -lh "$JNILIB_DIR"
echo "=== prepare_assets.sh завершён успешно ==="
