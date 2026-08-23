#!/bin/bash
# scripts/prepare_assets.sh
# Скачивает готовый ARM64 бинарник QEMU и создает Debian rootfs в формате tar.gz через Docker

set -e

PROJECT_ROOT="$(pwd)"
ASSETS_DIR="$PROJECT_ROOT/app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Скачивание готового qemu-aarch64 (ARM64) из Debian ==="
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

if [ ! -f "$QEMU_BIN" ]; then
    echo "Скачивание пакета qemu-user-static (arm64)..."
    
    QEMU_DEB_URL="http://ftp.de.debian.org/debian/pool/main/q/qemu/qemu-user-static_7.2+dfsg-7+deb12u18+b3_arm64.deb"
    QEMU_DEB_FILE="$ASSETS_DIR/qemu.deb"
    
    curl -L --fail -o "$QEMU_DEB_FILE" "$QEMU_DEB_URL" || {
        echo "❌ Не удалось скачать пакет qemu-user-static"
        exit 1
    }
    
    echo "Извлечение бинарника из .deb пакета..."
    EXTRACT_DIR="$ASSETS_DIR/qemu-extract"
    mkdir -p "$EXTRACT_DIR"
    
    dpkg-deb -x "$QEMU_DEB_FILE" "$EXTRACT_DIR"
    cp "$EXTRACT_DIR/usr/bin/qemu-aarch64-static" "$QEMU_BIN"
    chmod +x "$QEMU_BIN"
    
    rm -rf "$EXTRACT_DIR" "$QEMU_DEB_FILE"
    
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

echo "=== 2. Создание Debian 11 rootfs (tar.gz формат) через Docker ==="
ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.gz"

if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    echo "Извлечение rootfs из Docker образа debian:bullseye-slim (arm64)..."
    
    # Явно указываем платформу, чтобы на x86_64 раннере скачался и использовался именно arm64 образ
    docker pull --platform linux/arm64 debian:bullseye-slim
    
    # Создаем контейнер из arm64 образа (исправлено имя образа)
    docker create --platform linux/arm64 --name temp-debian-rootfs debian:bullseye-slim
    
    # Экспортируем файловую систему контейнера и сжимаем в gzip
    docker export temp-debian-rootfs | gzip > "$ROOTFS_ARCHIVE"
    
    # Удаляем временный контейнер
    docker rm temp-debian-rootfs
    
    # Проверка размера (минимальный debian должен быть > 20 МБ в сжатом виде)
    FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
    if [ "$FILE_SIZE" -lt 20000000 ]; then
        echo "❌ Файл слишком мал ($FILE_SIZE байт). Что-то пошло не так."
        rm -f "$ROOTFS_ARCHIVE"
        exit 1
    fi
    echo "✅ Debian rootfs получен (Размер: $((FILE_SIZE / 1024 / 1024)) МБ, формат: tar.gz)."
else
    echo "Debian rootfs уже существует, пропускаем."
fi

echo "=== 3. Очистка ==="
rm -f "$ASSETS_DIR/proot" "$ASSETS_DIR/busybox" "$ASSETS_DIR/toybox" "$ASSETS_DIR/debian-rootfs.tar.xz"

echo "=== Итог ==="
ls -lh "$ASSETS_DIR/"
echo "✅ Assets готовы."
