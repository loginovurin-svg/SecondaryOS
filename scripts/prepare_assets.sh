#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecondaryOS
# scripts/prepare_assets.sh — ВАРИАНТ B (рабочий)
# Готовый статический proot 5.3.0 + Debian 11 (bullseye) + busybox
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT/app/src/main/assets"
JNILIB_DIR="$ROOT/app/src/main/jniLibs/arm64-v8a"
WORK="$(mktemp -d)"

trap 'rm -rf "$WORK"' EXIT

echo "=== SecondaryOS prepare_assets (вариант B) ==="

mkdir -p "$ASSETS_DIR" "$JNILIB_DIR"
rm -f "$ASSETS_DIR/proot_static" "$JNILIB_DIR/libproot.so" \
      "$ASSETS_DIR/debian-rootfs.tar.xz" "$ASSETS_DIR/busybox"

# ------------------------------------------------------------
# 1. Готовый статический proot 5.3.0
# ------------------------------------------------------------
echo "=== Скачиваю готовый proot ==="
curl -sS -fL --retry 3 -o "$WORK/proot" \
    "https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-aarch64-static"

file "$WORK/proot" || true

cp "$WORK/proot" "$ASSETS_DIR/proot_static"
chmod 0755 "$ASSETS_DIR/proot_static"
cp "$WORK/proot" "$JNILIB_DIR/libproot.so"
chmod 0755 "$JNILIB_DIR/libproot.so"
echo "proot готов"

# ------------------------------------------------------------
# 2. Статический busybox для ARM64 (Android)
# ------------------------------------------------------------
echo "=== Скачиваю busybox ==="
curl -sS -fL --retry 3 -o "$WORK/busybox" \
    "https://busybox.net/downloads/binaries/1.35.0-aarch64-linux-android-musl/busybox"

chmod 0755 "$WORK/busybox"
cp "$WORK/busybox" "$ASSETS_DIR/busybox"
chmod 0755 "$ASSETS_DIR/busybox"
echo "busybox готов"

# ------------------------------------------------------------
# 3. Rootfs Debian 11 (bullseye)
# ------------------------------------------------------------
echo "=== Скачиваю Debian 11 rootfs ==="
ROOTFS_BASE_URL="https://images.linuxcontainers.org/images/debian/bullseye/arm64/default"

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
ls -lh "$ASSETS_DIR"
ls -lh "$JNILIB_DIR"
echo "=== prepare_assets.sh завершён успешно ==="
