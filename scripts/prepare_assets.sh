#!/bin/bash
# scripts/prepare_assets.sh
# Скачивает QEMU user-mode и Debian 11 rootfs в assets для встраивания в APK

set -e

ASSETS_DIR="app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Скачивание статического бинарника qemu-aarch64 ==="
QEMU_URL="https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static"
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

if [ ! -f "$QEMU_BIN" ]; then
    echo "Скачивание qemu-aarch64..."
    curl -L --fail -o "$QEMU_BIN" "$QEMU_URL"
    chmod +x "$QEMU_BIN"
    
    # Проверка архитектуры
    ARCH_CHECK=$(file "$QEMU_BIN" | grep -i "aarch64" || true)
    if [ -z "$ARCH_CHECK" ]; then
        echo "⚠️ ВНИМАНИЕ: qemu-aarch64 не является ARM64-бинарником!"
        file "$QEMU_BIN"
    else
        echo "✅ qemu-aarch64 загружен (ARM64)."
    fi
else
    echo "qemu-aarch64 уже существует, пропускаем."
fi

echo "=== 2. Скачивание Debian 11 rootfs (arm64, tar.gz) ==="
# Официальный nocloud образ Debian 11 для arm64 в формате tar.gz
# Размер ~180-200 МБ. APK будет большим, но rootfs будет встроен.
ROOTFS_URL="https://cdimage.debian.org/cdimage/cloud/bullseye/latest/debian-11-nocloud-arm64.tar.gz"
ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.gz"

if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    echo "Скачивание Debian rootfs (это займёт время, ~180 МБ)..."
    curl -L --fail -o "$ROOTFS_ARCHIVE" "$ROOTFS_URL"
    
    # Проверка размера: должно быть больше 100 МБ
    FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
    if [ "$FILE_SIZE" -lt 100000000 ]; then
        echo "❌ ОШИБКА: Файл слишком мал ($FILE_SIZE байт). Возможно, ссылка устарела."
        rm -f "$ROOTFS_ARCHIVE"
        exit 1
    fi
    echo "✅ Debian rootfs загружен (Размер: $((FILE_SIZE / 1024 / 1024)) МБ)."
else
    echo "Debian rootfs уже существует, пропускаем."
fi

echo "=== 3. Очистка старых артефактов ==="
rm -f "$ASSETS_DIR/proot"
rm -f "$ASSETS_DIR/busybox"
rm -f "$ASSETS_DIR/toybox"
rm -f "$ASSETS_DIR/debian-rootfs.tar.xz"

echo "=== Итог ==="
ls -lh "$ASSETS_DIR/"
echo "✅ Assets готовы. APK будет включать rootfs."
