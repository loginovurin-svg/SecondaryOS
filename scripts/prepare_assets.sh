#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecondaryOS
# scripts/prepare_assets.sh
#
# Теперь proot НЕ скачивается, а собирается кросс-компилятором
# из исходников ветки Termux (там патчи для Android, включая
# обход seccomp/rseq). Статически, musl, aarch64.
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

# ------------------------------------------------------------
# 1. Скачиваем musl кросс-тулчейн для aarch64 (один архив)
# ------------------------------------------------------------
echo "=== Скачиваю musl cross toolchain ==="
curl -fL --retry 3 -o "$WORK/musl.tgz" \
    "https://musl.cc/aarch64-linux-musl-cross.tgz"
tar -xzf "$WORK/musl.tgz" -C "$WORK"
CC="$WORK/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc"
echo "Компилятор: $CC"
"$CC" --version | head -n 1

# ------------------------------------------------------------
# 2. Скачиваем и компилируем talloc (один .c файл)
# ------------------------------------------------------------
echo "=== Собираю talloc ==="
curl -fL --retry 3 -o "$WORK/talloc.tar.gz" \
    "https://www.samba.org/ftp/talloc/talloc-2.4.2.tar.gz"
tar -xzf "$WORK/talloc.tar.gz" -C "$WORK"
TALLOC_DIR="$WORK/talloc-2.4.2"

"$CC" -c "$TALLOC_DIR/talloc.c" \
    -I "$TALLOC_DIR" \
    -D_GNU_SOURCE -O2 \
    -o "$WORK/talloc.o"
echo "talloc.o готов"

# ------------------------------------------------------------
# 3. Скачиваем исходники proot из ветки Termux
# ------------------------------------------------------------
echo "=== Скачиваю proot (termux fork) ==="
curl -fL --retry 3 -o "$WORK/proot.tar.gz" \
    "https://github.com/termux/proot/archive/refs/heads/master.tar.gz"
tar -xzf "$WORK/proot.tar.gz" -C "$WORK"
PROOT_SRC="$(echo "$WORK"/proot-*/src)"
echo "Исходники: $PROOT_SRC"

# ------------------------------------------------------------
# 4. Компилируем proot статически одним вызовом
# ------------------------------------------------------------
echo "=== Компилирую proot ==="
cd "$PROOT_SRC"

# Все .c файлы proot
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
# 6. Debian rootfs (как раньше, с images.linuxcontainers.org)
# ------------------------------------------------------------
echo "=== Получение Debian rootfs ==="
ROOTFS_URL="${ROOTFS_URL:-}"

if [[ -z "$ROOTFS_URL" ]]; then
    ROOTFS_BASE_URL="https://images.linuxcontainers.org/images/debian/bookworm/arm64/default"
    LATEST_DIR=$(curl -fsSL "$ROOTFS_BASE_URL/" | grep -oP '(?<=href=")[0-9]{8}_[0-9]{2}%3A[0-9]{2}' | sort | tail -n 1)
    if [[ -z "$LATEST_DIR" ]]; then
        echo "ОШИБКА: не найдена папка rootfs"
        exit 1
    fi
    ROOTFS_URL="$ROOTFS_BASE_URL/$LATEST_DIR/rootfs.tar.xz"
    echo "Найдена сборка: $LATEST_DIR"
fi

curl -fL --retry 3 -o "$WORK/rootfs.tar.xz" "$ROOTFS_URL"
cp "$WORK/rootfs.tar.xz" "$ASSETS_DIR/debian-rootfs.tar.xz"

echo
echo "Готовые assets:"
ls -lh "$ASSETS_DIR"
echo "Готовые jniLibs:"
ls -lh "$JNILIB_DIR"
echo "=== prepare_assets.sh завершён успешно ==="
