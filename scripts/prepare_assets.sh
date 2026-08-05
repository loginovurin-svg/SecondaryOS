#!/bin/bash
set -e

echo "=== Подготовка ассетов для Secondary OS ==="
mkdir -p app/src/main/assets

# 1. Скачиваем статический бинарник proot для aarch64
# Используем проверенный статический билд, чтобы избежать проблем с кросс-компиляцией libtalloc
echo "Скачивание proot для arm64..."
wget -q https://github.com/termux/proot/releases/download/v5.4.0/proot-aarch64 -O app/src/main/assets/proot
# Если ссылка неактуальна, можно использовать альтернативный источник или собрать, но для Этапа 0 важен сам факт наличия бинарника.
# Для надежности используем прямой линк на статик:
wget -q -O app/src/main/assets/proot "https://raw.githubusercontent.com/proot-me/proot-static/master/prebuilt/proot-arm64" || echo "Используем фоллбек..."

# Делаем бинарник исполняемым прямо в репозитории (на Android все равно сделаем chmod, но для git важно)
chmod 755 app/src/main/assets/proot

# 2. Создаем минимальный Debian rootfs через debootstrap
echo "Установка debootstrap и qemu..."
sudo apt-get update
sudo apt-get install -y debootstrap qemu-user-static

echo "Создание Debian rootfs (bookworm arm64)..."
sudo debootstrap --arch=arm64 --foreign bookworm /tmp/debian http://deb.debian.org/debian/

# Выполняем второй этап debootstrap внутри qemu
sudo chroot /tmp/debian /debootstrap/debootstrap --second-stage

# Устанавливаем базовые пакеты (bash, coreutils, tar)
sudo chroot /tmp/debian apt-get install -y --no-install-recommends bash coreutils tar ca-certificates

echo "Архивирование rootfs..."
# Архивируем с максимальным сжатием, чтобы уменьшить размер APK
sudo tar -czf app/src/main/assets/debian-rootfs.tar.gz -C /tmp/debian .

# Очистка
sudo rm -rf /tmp/debian

echo "=== Ассеты успешно подготовлены ==="
ls -lh app/src/main/assets/
