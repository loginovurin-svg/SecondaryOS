#!/bin/bash
# scripts/prepare_assets.sh
# Скачивает готовый ARM64 бинарник QEMU и Debian rootfs

set -e

PROJECT_ROOT="$(pwd)"
ASSETS_DIR="$PROJECT_ROOT/app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Скачивание готового qemu-aarch64 (ARM64) ==="
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

if [ ! -f "$QEMU_BIN" ]; then
    echo "Скачивание qemu-aarch64 из Termux..."
    
    # Termux предоставляет готовые ARM64 бинарники
    # Используем пакет qemu-user-static
    QEMU_URL="https://github.com/nicbarker/qemu-aarch64-static/releases/download/v1.0.0/qemu-aarch64-static"
    
    curl -L --fail -o "$QEMU_BIN" "$QEMU_URL" || {
        echo "❌ Не удалось скачать из nicbarker. Пробуем альтернативу..."
        
        # Альтернатива: Debian package
        QEMU_URL="http://ftp.debian.org/debian/pool/main/q/qemu/qemu-user-static_7.2.0+dfsg-7+deb12u8_arm64.deb"
        curl -L --fail -o "$ASSETS_DIR/qemu.deb" "$QEMU_URL" || {
            echo "❌ Все источники недоступны"
            exit 1
        }
        
        # Извлекаем бинарник из deb
        cd "$ASSETS_DIR"
        ar x qemu.deb
        tar -xf data.tar.xz --wildcards './usr/bin/qemu-aarch64-static' --strip-components=3
        mv qemu-aarch64-static qemu-aarch64
        chmod +x qemu-aarch64
        rm -f qemu.deb data.tar.xz control.tar.xz debian-binary
        cd "$PROJECT_ROOT"
    }
    
    chmod +x "$QEMU_BIN"
    
    # Проверка архитектуры
    if file "$QEMU_BIN" | grep -q "aarch64\|ARM64\|AArch64"; then
        echo "✅ qemu-aarch64 загружен (ARM64)."
    else
        echo "⚠️ ВНИМАНИЕ: файл может быть не для ARM64"
        file "$QEMU_BIN"
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
        echo "❌ Официальный Debian недоступен."
        rm -f "$ROOTFS_ARCHIVE"
        exit 1
    }
    
    FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
    if [ "$FILE_SIZE" -lt 100000000 ]; then
        echo "❌ Файл слишком мал ($FILE_SIZE байт)."
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
