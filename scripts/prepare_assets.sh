#!/bin/bash
set -e

echo "=== Сборка настоящего proot ==="
chmod +x scripts/build_proot.sh
./scripts/build_proot.sh

echo "=== Создание Debian rootfs (пока заглушка, на след. шаге сделаем debootstrap) ==="
# Временно оставляем минимальный rootfs, чтобы проверить что proot запускается
ROOTFS_DIR=app/src/main/assets/rootfs
mkdir -p $ROOTFS_DIR
cd $ROOTFS_DIR

# Скачаем минимальный pre-built arm64 rootfs, чтобы сразу тестировать
# (на следующем шаге заменим на свой debootstrap)
if [ ! -f rootfs.tar.gz ]; then
    echo "Скачиваем минимальный Debian arm64 rootfs для теста..."
    # Можно использовать любой arm64 rootfs, например из proot-distro
    curl -L -o rootfs.tar.gz "https://github.com/termux/proot-distro/releases/download/v4.8.0/debian-bookworm-arm64-pd-v4.8.0.tar.gz" || echo "Не удалось скачать — создадим минимальный"
fi

cd ../../..
echo "=== Подготовка завершена ==="
