#!/bin/bash
# scripts/prepare_assets.sh
# Цель: Подготовка assets для SecondaryOS (Фаза 1: QEMU user-mode + Debian rootfs)

set -e

ASSETS_DIR="app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Скачивание статического бинарника qemu-aarch64 ==="
# Используем стабильный релиз. 
# ПРОВЕРКА: убедитесь, что скачанный файл является ARM64-бинарником (file qemu-aarch64 должен показать aarch64).
QEMU_URL="https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static"
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

if [ ! -f "$QEMU_BIN" ]; then
    echo "Скачивание qemu-aarch64..."
    curl -L -o "$QEMU_BIN" "$QEMU_URL"
    chmod +x "$QEMU_BIN"
    echo "qemu-aarch64 успешно загружен."
else
    echo "qemu-aarch64 уже существует, пропускаем."
fi

echo "=== 2. Скачивание rootfs Debian 11 (bullseye) ==="
# Используем проверенный минимальный образ Debian для arm64
ROOTFS_URL="https://github.com/AndronixApp/Andronix-Origin/raw/master/Rootfs/Debian/debian-11-arm64.tar.xz"
ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.xz"

if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    echo "Скачивание Debian 11 rootfs..."
    curl -L -o "$ROOTFS_ARCHIVE" "$ROOTFS_URL"
    echo "Debian rootfs успешно загружен."
else
    echo "Debian rootfs уже существует, пропускаем."
fi

echo "=== 3. Очистка от старых артефактов ==="
# Мы больше не используем proot и самосборные утилиты из-за seccomp и несовместимости glibc
rm -f "$ASSETS_DIR/proot"
rm -f "$ASSETS_DIR/busybox"
rm -f "$ASSETS_DIR/toybox"

echo "=== Подготовка assets завершена ==="
