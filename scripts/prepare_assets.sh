#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecondaryOS
# scripts/prepare_assets.sh — СБОРКА PROOT ИЗ ИСХОДНИКОВ
#
# proot из ветки termux/proot (патчи под Android).
# talloc компилируется одним вызовом gcc с флагами вместо waf.
# proot требует build.h (генерируется waf) — создаём заглушку.
# Rootfs: Debian 11 (bullseye).
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT/app/src/main/assets"
JNILIB_DIR="$ROOT/app/src/main/jniLibs/arm64-v8a"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

echo "=== SecondaryOS prepare_assets (сборка proot) ==="
echo "ROOT: $ROOT"

mkdir -p "$ASSETS_DIR" "$JNILIB_DIR"
rm -f "$ASSETS_DIR/proot_static" "$JNILIB_DIR/libproot.so" \
      "$ASSETS_DIR/debian-rootfs.tar.xz"

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
fi

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
    echo "ОШИБКА: не удалось скачать $out"
    return 1
}

# ------------------------------------------------------------
# 1. Кросс-компилятор aarch64 из репозитория Ubuntu
# ------------------------------------------------------------
echo "=== Устанавливаю gcc-aarch64-linux-gnu ==="
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq gcc-aarch64-linux-gnu libc6-dev-arm64-cross

CC="aarch64-linux-gnu-gcc"
AR="aarch64-linux-gnu-ar"
echo "Компилятор: $CC"
"$CC" --version | head -n 1

# ------------------------------------------------------------
# 2. talloc + заглушка replace.h + флаги вместо waf
# ------------------------------------------------------------
echo "=== Скачиваю talloc ==="
download_with_fallback "$WORK/talloc.tar.gz" \
    "https://www.samba.org/ftp/talloc/talloc-2.4.2.tar.gz" \
    "https://ftp.samba.org/pub/talloc/talloc-2.4.2.tar.gz"

tar -xzf "$WORK/talloc.tar.gz" -C "$WORK"
TALLOC_DIR="$WORK/talloc-2.4.2"

# Заглушка вместо libreplace из Samba
REPLACE_DIR="$WORK/libreplace"
mkdir -p "$REPLACE_DIR"
cat > "$REPLACE_DIR/replace.h" <<'EOF'
#ifndef _REPLACE_H
#define _REPLACE_H
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <errno.h>
#include <unistd.h>
#include <sys/types.h>
#endif
EOF

echo "=== Компилирую talloc ==="
"$CC" -c "$TALLOC_DIR/talloc.c" \
    -I "$TALLOC_DIR" -I "$REPLACE_DIR" \
    -D_GNU_SOURCE -O2 \
    -include limits.h \
    -DTALLOC_BUILD_VERSION_MAJOR=2 \
    -DTALLOC_BUILD_VERSION_MINOR=4 \
    -DTALLOC_BUILD_VERSION_RELEASE=2 \
    -D'MIN(a,b)=((a)<(b)?(a):(b))' \
    -D'MAX(a,b)=((a)>(b)?(a):(b))' \
    -o "$WORK/talloc.o"

# Статическая библиотека и заголовок в одном каталоге
LIBDIR="$WORK/aarch64lib"
mkdir -p "$LIBDIR"
"$AR" rcs "$LIBDIR/libtalloc.a" "$WORK/talloc.o"
cp "$TALLOC_DIR/talloc.h" "$LIBDIR/"
echo "libtalloc.a готова"

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
# 4. Создаём build.h (заглушка вместо waf)
# ------------------------------------------------------------
echo "=== Создаю build.h ==="
BUILDDIR="$WORK/build"
mkdir -p "$BUILDDIR"

# build.h содержит макросы, которые обычно генерирует waf configure.
# Включаем все HAVE_* для aarch64 Linux (x86_64-хост с кросс-компилятором).
cat > "$BUILDDIR/build.h" <<'EOF'
#ifndef BUILD_H
#define BUILD_H

#define VERSION "5.4.0-termux"

/* Архитектура */
#define ARCH_arm64 1

/* Системные вызовы и функции */
#define HAVE_PROCESS_VM_READV 1
#define HAVE_PROCESS_VM_WRITEV 1
#define HAVE_GETAUXVAL 1
#define HAVE_MKNOD 1
#define HAVE_MKNODAT 1
#define HAVE_PIVOT_ROOT 1
#define HAVE_OPENAT 1
#define HAVE_FSTATAT 1
#define HAVE_UNLINKAT 1
#define HAVE_RENAMEAT 1
#define HAVE_LINKAT 1
#define HAVE_SYMLINKAT 1
#define HAVE_READLINKAT 1
#define HAVE_MKDIRAT 1
#define HAVE_FCHMODAT 1
#define HAVE_FCHOWNAT 1
#define HAVE_UTIMENSAT 1
#define HAVE_FACCESSAT 1
#define HAVE_PREAD 1
#define HAVE_PWRITE 1
#define HAVE_FUTIMENS 1

/* Seccomp для обхода фильтров Android */
#define HAVE_SECCOMP_FILTER 1

/* ptrace options */
#define HAVE_PTRACE_O_TRACESYSGOOD 1
#define HAVE_PTRACE_O_TRACECLONE 1
#define HAVE_PTRACE_O_TRACEFORK 1
#define HAVE_PTRACE_O_TRACEVFORK 1
#define HAVE_PTRACE_O_TRACEEXEC 1
#define HAVE_PTRACE_O_TRACEEXIT 1

/* Прочее */
#define HAVE_STRLCPY 0
#define HAVE_STRLCAT 0
#define HAVE_PROGRAM_INVOCATION_NAME 1

#endif /* BUILD_H */
EOF

# ------------------------------------------------------------
# 5. Компилируем proot статически одним вызовом gcc
# ------------------------------------------------------------
echo "=== Компилирую proot ==="
cd "$PROOT_SRC"

SRCS=$(find . -name '*.c' | sort)
echo "Файлов для компиляции: $(echo "$SRCS" | wc -l)"

"$CC" -O2 -static \
    -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 \
    -DPROOT_VERSION='"5.4.0-termux"' \
    -I. -I "$LIBDIR" -I "$REPLACE_DIR" -I "$BUILDDIR" \
    $SRCS "$LIBDIR/libtalloc.a" \
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
# 6. Кладём proot в assets и jniLibs
# ------------------------------------------------------------
cp "$WORK/proot" "$ASSETS_DIR/proot_static"
chmod 0755 "$ASSETS_DIR/proot_static"

cp "$WORK/proot" "$JNILIB_DIR/libproot.so"
chmod 0755 "$JNILIB_DIR/libproot.so"
echo "proot_static и libproot.so готовы"
echo

# ------------------------------------------------------------
# 7. Rootfs Debian 11 (bullseye)
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
