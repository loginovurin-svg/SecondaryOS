#!/bin/bash
# scripts/prepare_assets.sh
# Принудительно скачивает ARM64 QEMU и создает Debian rootfs

set -e

PROJECT_ROOT="$(pwd)"
ASSETS_DIR="$PROJECT_ROOT/app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Скачивание готового qemu-aarch64 (ARM64) из Debian ==="
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

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
else
    echo "❌ ОШИБКА: файл не является ARM64 бинарником!"
    exit 1
fi

SIZE=$(stat -c%s "$QEMU_BIN" 2>/dev/null || stat -f%z "$QEMU_BIN")
echo "  Размер QEMU: $((SIZE / 1024 / 1024)) МБ"


echo "=== 2. Создание Debian 11 rootfs (tar.gz) через Docker ==="
# ПРИНУДИТЕЛЬНО удаляем любые старые версии rootfs, чтобы избежать кэширования мусора
rm -f "$ASSETS_DIR/debian-rootfs.tar.gz"
rm -f "$ASSETS_DIR/debian-rootfs.tar"
rm -f "$ASSETS_DIR/debian-rootfs.tar.xz"

ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.gz"
echo "Извлечение rootfs из Docker образа debian:bullseye-slim (arm64)..."

docker pull --platform linux/arm64 debian:bullseye-slim
docker create --platform linux/arm64 --name temp-debian-rootfs debian:bullseye-slim
docker export temp-debian-rootfs | gzip > "$ROOTFS_ARCHIVE"
docker rm temp-debian-rootfs

FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
if [ "$FILE_SIZE" -lt 20000000 ]; then
    echo "❌ Файл rootfs слишком мал ($FILE_SIZE байт). Ошибка Docker."
    exit 1
fi
echo "✅ Debian rootfs получен (Размер: $((FILE_SIZE / 1024 / 1024)) МБ)."


echo "=== 3. Итог ==="
ls -lh "$ASSETS_DIR/"
echo "✅ Assets готовы к упаковке в APK."
