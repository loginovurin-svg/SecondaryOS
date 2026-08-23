#!/bin/bash
# scripts/prepare_assets.sh
# Скачивает готовый ARM64 бинарник QEMU напрямую из Debian и скачивает rootfs

set -e

PROJECT_ROOT="$(pwd)"
ASSETS_DIR="$PROJECT_ROOT/app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Скачивание готового qemu-aarch64 (ARM64) из Debian ==="
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

if [ ! -f "$QEMU_BIN" ]; then
    echo "Скачивание пакета qemu-user-static (arm64) напрямую из Debian..."
    
    # Прямая ссылка на стабильный arm64 пакет Debian Bookworm
    QEMU_DEB_URL="http://ftp.debian.org/debian/pool/main/q/qemu/qemu-user-static_7.2.0+dfsg-7+deb12u7_arm64.deb"
    QEMU_DEB_FILE="$ASSETS_DIR/qemu.deb"
    
    curl -L --fail -o "$QEMU_DEB_FILE" "$QEMU_DEB_URL" || {
        echo "❌ Не удалось скачать пакет qemu-user-static"
        exit 1
    }
    
    echo "Извлечение бинарника из .deb пакета..."
    # Создаем временную директорию для распаковки
    EXTRACT_DIR="$ASSETS_DIR/qemu-extract"
    mkdir -p "$EXTRACT_DIR"
    
    # Распаковываем deb файл (утилита dpkg-deb есть на всех ubuntu-раннерах по умолчанию)
    dpkg-deb -x "$QEMU_DEB_FILE" "$EXTRACT_DIR"
    
    # Копируем нужный бинарник и переименовываем для удобства
    cp "$EXTRACT_DIR/usr/bin/qemu-aarch64-static" "$QEMU_BIN"
    chmod +x "$QEMU_BIN"
    
    # Очистка временных файлов
    rm -rf "$EXTRACT_DIR" "$QEMU_DEB_FILE"
    
    # Проверка архитектуры
    if file "$QEMU_BIN" | grep -qi "aarch64\|arm64"; then
        echo "✅ qemu-aarch64 успешно получен (ARM64)."
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
