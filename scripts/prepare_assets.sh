#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecondaryOS
# scripts/prepare_assets.sh — ВАРИАНТ B
#
# НОЛЬ компиляции:
# - готовый статический proot 5.3.0 (официальный релиз)
# - готовый rootfs Debian 11 (bullseye): glibc 2.31, НЕТ rseq,
#   поэтому старый proot работает без костылей
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT/app/src/main/assets"
JNILIB_DIR="$ROOT/app/src/main/jniLibs/arm64-v8a"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

echo "=== SecondaryOS prepare_assets (вариант B) ==="
echo "ROOT: $ROOT"

mkdir -p "$ASSETS_DIR" "$JNILIB_DIR"
rm -f "$ASSETS_DIR/proot_static" "$JNILIB_DIR/libproot.so" \
      "$ASSETS_DIR/debian-rootfs.tar.xz"

# ------------------------------------------------------------
# 1. Готовый статический proot 5.3.0
# ------------------------------------------------------------
echo "=== Скачиваю готовый proot ==="
PROOT_URL="https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-aarch64-static"

curl -sS -fL --retry 3 -o "$WORK/proot" "$PROOT_URL"

echo "Проверка proot:"
file "$WORK/proot" || true

if ! file "$WORK/proot" | grep -qi 'aarch64'; then
    echo "ОШИБКА: proot не aarch64"
    exit 1
fi
if ! file "$WORK/proot" | grep -qi 'statically linked'; then
    echo "ОШИБКА: proot не статический"
    exit 1
fi

cp "$WORK/proot" "$ASSETS_DIR/proot_static"
chmod 0755 "$ASSETS_DIR/proot_static"

cp "$WORK/proot" "$JNILIB_DIR/libproot.so"
chmod 0755 "$JNILIB_DIR/libproot.so"
echo "proot_static и libproot.so готовы"
echo

# ------------------------------------------------------------
# 2. Готовый rootfs Debian 11 (bullseye) arm64
# ------------------------------------------------------------
echo "=== Скачиваю Debian 11 rootfs ==="
ROOTFS_BASE_URL="https://images.linuxcontainers.org/images/debian/bullseye/arm64/default"

# Сервер кодирует двоеточие как %3A в HTML
LATEST_DIR=$(curl -sS -fL "$ROOTFS_BASE_URL/" \
    | grep -oP '(?<=href=")[0-9]{8}_[0-9]{2}%3A[0-9]{2}' \
    | sort | tail -n 1)

if [[ -z "$LATEST_DIR" ]]; then
    echo "ОШИБКА: не найдена папка с rootfs bullseye"
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
