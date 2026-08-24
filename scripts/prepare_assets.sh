#!/bin/bash
# scripts/prepare_assets.sh
# ЯДЕРНЫЙ ВАРИАНТ: Полная очистка и принудительная загрузка правильных файлов

set -e

PROJECT_ROOT="$(pwd)"
ASSETS_DIR="$PROJECT_ROOT/app/src/main/assets"

echo "=== 0. ПРИНУДИТЕЛЬНАЯ ОЧИСТКА ПАПКИ ASSETS ==="
mkdir -p "$ASSETS_DIR"
# Удаляем ВСЁ, что там было, чтобы исключить кэш и старые битые файлы
rm -rf "$ASSETS_DIR"/*
echo "Папка очищена."

echo "=== 1. СКАЧИВАНИЕ QEMU (ARM64) ==="
QEMU_DEB_URL="http://ftp.de.debian.org/debian/pool/main/q/qemu/qemu-user-static_7.2+dfsg-7+deb12u18+b3_arm64.deb"
QEMU_DEB_FILE="$ASSETS_DIR/qemu.deb"

echo "Скачивание deb-пакета..."
curl -L --fail -o "$QEMU_DEB_FILE" "$QEMU_DEB_URL"

echo "Извлечение бинарника..."
EXTRACT_DIR="$ASSETS_DIR/qemu-extract"
mkdir -p "$EXTRACT_DIR"
dpkg-deb -x "$QEMU_DEB_FILE" "$EXTRACT_DIR"
cp "$EXTRACT_DIR/usr/bin/qemu-aarch64-static" "$ASSETS_DIR/qemu-aarch64"
chmod +x "$ASSETS_DIR/qemu-aarch64"
rm -rf "$EXTRACT_DIR" "$QEMU_DEB_FILE"

echo "Проверка архитектуры QEMU:"
file "$ASSETS_DIR/qemu-aarch64"

echo "=== 2. СОЗДАНИЕ DEBIAN ROOTFS (TAR.GZ) ЧЕРЕЗ DOCKER ==="
ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.gz"

echo "Запуск Docker контейнера debian:bullseye-slim (arm64)..."
docker pull --platform linux/arm64 debian:bullseye-slim
docker create --platform linux/arm64 --name temp-debian-rootfs debian:bullseye-slim

echo "Экспорт файловой системы и сжатие в gzip..."
docker export temp-debian-rootfs | gzip > "$ROOTFS_ARCHIVE"
docker rm temp-debian-rootfs

echo "=== 3. ФИНАЛЬНАЯ ПРОВЕРКА РАЗМЕРОВ ПЕРЕД СБОРКОЙ ==="
echo "Содержимое папки assets:"
ls -lh "$ASSETS_DIR"
echo "Общий размер папки assets:"
du -sh "$ASSETS_DIR"

# Жесткая проверка: если rootfs меньше 20 МБ, прерываем сборку
FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
if [ "$FILE_SIZE" -lt 20000000 ]; then
    echo "❌ КРИТИЧЕСКАЯ ОШИБКА: Rootfs весит меньше 20 МБ ($FILE_SIZE байт). Сборка прервана."
    exit 1
fi

echo "✅ Assets успешно подготовлены и готовы к упаковке в APK."
