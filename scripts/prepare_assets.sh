#!/bin/bash
# scripts/prepare_assets.sh
# Получает ARM64 бинарник QEMU через Docker и скачивает Debian rootfs

set -e

PROJECT_ROOT="$(pwd)"
ASSETS_DIR="$PROJECT_ROOT/app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Получение qemu-aarch64 (ARM64) через Docker ==="
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

if [ ! -f "$QEMU_BIN" ]; then
    echo "Извлечение qemu-aarch64 из Docker образа multiarch/qemu-user-static..."
    
    # Используем официальный образ multiarch, который содержит статические бинарники для всех архитектур
    # --platform linux/arm64 гарантирует, что мы получим ARM64 версию
    docker run --rm --platform linux/arm64 multiarch/qemu-user-static:latest \
        cat /usr/bin/qemu-aarch64-static > "$QEMU_BIN"
    
    chmod +x "$QEMU_BIN"
    
    # Проверка архитектуры
    if file "$QEMU_BIN" | grep -q "aarch64\|ARM64\|AArch64"; then
        echo "✅ qemu-aarch64 получен (ARM64)."
        file "$QEMU_BIN"
    else
        echo "❌ ОШИБКА: файл не является ARM64 бинарником!"
        file "$QEMU_BIN"
        exit 1
    fi
    
    SIZE=$(stat -c%s "$QEMU_BIN" 2>/dev/null || stat -f%z "$QEMU_BIN")
    echo "  Размер: $((SIZE / 1024 / 1024)) МБ"
else
    echo "qemu-aarch64 уже существует, пропускаем."
fi

echo "=== 2. Скачивание Debian 11 rootfs ==="
ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.xz"

if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    echo "Скачивание Debian rootfs..."
    
    ROOTFS_URL="https://cdimage.debian.org/cdimage/cloud/bullseye/latest/debian-11-nocloud-arm64.tar.xz"
    
    curl -L --fail -o "$ROOTFS_ARCHIVE" "$ROOTFS_URL" || {
        echo " Официальный Debian недоступен."
        rm -f "$ROOTFS_ARCHIVE"
        exit 1
    }
    
    FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
    if [ "$FILE_SIZE" -lt 100000000 ]; then
        echo " Файл слишком мал ($FILE_SIZE байт)."
        rm -f "$ROOTFS_ARCHIVE"
        exit 1
    fi
    echo "✅ Debian rootfs загружен (Размер: $((FILE_SIZE / 1024 / 1024)) МБ)."
else
    echo "Debian rootfs уже существует, пропускаем."
fi

echo "=== 3. Очистка ==="
rm -f "$ASSETS_DIR/proot" "$ASSETS_DIR/busybox" "$ASSETS_DIR/toybox"

echo "=== Итог ==="
ls -lh "$ASSETS_DIR/"
echo "✅ Assets готовы."
