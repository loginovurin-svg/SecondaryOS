#!/bin/bash
# scripts/prepare_assets.sh
# Цель: Подготовка assets для SecondaryOS (Фаза 1: QEMU user-mode + Debian rootfs)

set -e

ASSETS_DIR="app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Скачивание статического бинарника qemu-aarch64 ==="
QEMU_URL="https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static"
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

if [ ! -f "$QEMU_BIN" ]; then
    echo "Скачивание qemu-aarch64..."
    curl -L -o "$QEMU_BIN" "$QEMU_URL"
    chmod +x "$QEMU_BIN"
    
    # ПРОВЕРКА АРХИТЕКТУРЫ: бинарник должен быть скомпилирован для ARM64 (хост), 
    # а не для x86_64. Иначе на устройстве Helio G99 он не запустится.
    ARCH_CHECK=$(file "$QEMU_BIN" | grep -i "aarch64" || true)
    if [ -z "$ARCH_CHECK" ]; then
        echo "⚠️ ВНИМАНИЕ: Скачанный qemu-aarch64 НЕ является ARM64-бинарником!"
        echo "Текущая информация о файле:"
        file "$QEMU_BIN"
        echo "Для работы на Helio G99 необходим бинарник, скомпилированный под aarch64."
        echo "Рекомендуется взять бинарник из репозитория Termux или скомпилировать его."
    else
        echo "✅ qemu-aarch64 успешно загружен и является ARM64-бинарником."
    fi
else
    echo "qemu-aarch64 уже существует, пропускаем."
fi

echo "=== 2. Скачивание rootfs Debian 11 (bullseye) arm64 ==="
# Официальный образ Debian Cloud Images (nocloud, без лишних сервисов, ~180 МБ)
ROOTFS_URL="https://cdimage.debian.org/cdimage/cloud/bullseye/latest/debian-11-nocloud-arm64.tar.xz"
ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.xz"

if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    echo "Скачивание Debian 11 rootfs (это может занять время, размер ~180 МБ)..."
    curl -L -o "$ROOTFS_ARCHIVE" "$ROOTFS_URL"
    
    # ПРОВЕРКА РАЗМЕРА: файл должен быть больше 100 МБ (104857600 байт)
    FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
    if [ "$FILE_SIZE" -lt 100000000 ]; then
        echo "❌ ОШИБКА: Размер загруженного файла слишком мал ($FILE_SIZE байт)."
        echo "Скорее всего, ссылка устарела или вернула HTML-страницу ошибки."
        rm -f "$ROOTFS_ARCHIVE"
        exit 1
    fi
    echo "✅ Debian rootfs успешно загружен (Размер: $FILE_SIZE байт)."
else
    echo "Debian rootfs уже существует, пропускаем."
fi

echo "=== 3. Очистка от старых артефактов ==="
rm -f "$ASSETS_DIR/proot"
rm -f "$ASSETS_DIR/busybox"
rm -f "$ASSETS_DIR/toybox"

echo "=== Подготовка assets завершена успешно ==="
