#!/bin/bash
# scripts/prepare_assets.sh
# Скачивает QEMU user-mode (ARM64) и Debian 11 rootfs в assets

set -e

ASSETS_DIR="app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Скачивание qemu-aarch64 (ARM64 из Termux) ==="
# Termux предоставляет бинарники, скомпилированные ДЛЯ ARM64
QEMU_URL="https://github.com/termux/termux-packages/releases/download/qemu-8.2.3-3/qemu-user-static_8.2.3-3_aarch64.deb"
QEMU_DEB="$ASSETS_DIR/qemu.deb"

if [ ! -f "$ASSETS_DIR/qemu-aarch64" ]; then
    echo "Скачивание qemu из Termux..."
    curl -L --fail -o "$QEMU_DEB" "$QEMU_URL" || {
        echo "❌ Не удалось скачать из Termux. Пробуем альтернативу..."
        # Альтернатива: официальный пакет Debian
        QEMU_URL="http://ftp.us.debian.org/debian/pool/main/q/qemu/qemu-user-static_7.2.0+ds-8+deb12u7_arm64.deb"
        curl -L --fail -o "$QEMU_DEB" "$QEMU_URL"
    }
    
    # Извлекаем бинарник из .deb пакета
    echo "Извлечение qemu-aarch64 из deb-пакета..."
    cd "$ASSETS_DIR"
    ar x qemu.deb
    tar -xf data.tar.* --wildcards './usr/bin/qemu-aarch64-static' --strip-components=3
    mv qemu-aarch64-static qemu-aarch64
    chmod +x qemu-aarch64
    
    # Очистка
    rm -f qemu.deb data.tar.* control.tar.* debian-binary
    
    # Проверка
    if file qemu-aarch64 | grep -q "aarch64\|ARM64"; then
        echo "✅ qemu-aarch64 загружен (ARM64)."
    else
        echo "⚠️ ВНИМАНИЕ: файл может быть не для ARM64"
        file qemu-aarch64
    fi
    cd - > /dev/null
else
    echo "qemu-aarch64 уже существует, пропускаем."
fi

echo "=== 2. Скачивание Debian 11 rootfs ==="
ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.xz"

if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    echo "Скачивание Debian rootfs..."
    
    # Пробуем официальный Debian
    ROOTFS_URL="https://cdimage.debian.org/cdimage/cloud/bullseye/latest/debian-11-nocloud-arm64.tar.xz"
    
    if ! curl -L --fail -o "$ROOTFS_ARCHIVE" "$ROOTFS_URL"; then
        echo "❌ Официальный Debian недоступен. Пробуем Andronix..."
        rm -f "$ROOTFS_ARCHIVE"
        ROOTFS_URL="https://github.com/AndronixApp/Andronix-Origin/raw/master/Rootfs/Debian/debian-11-arm64.tar.xz"
        curl -L --fail -o "$ROOTFS_ARCHIVE" "$ROOTFS_URL" || {
            echo "❌ Все источники недоступны"
            exit 1
        }
    fi
    
    # Проверка размера
    FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
    if [ "$FILE_SIZE" -lt 10000000 ]; then
        echo "❌ Файл слишком мал ($FILE_SIZE байт)"
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
