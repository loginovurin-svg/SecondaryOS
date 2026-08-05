#!/bin/bash
set -e

echo "=== Подготовка ассетов для Secondary OS ==="
mkdir -p app/src/main/assets

# 1. Скачиваем статический бинарник proot для aarch64
echo "Скачивание proot для arm64..."

# Пробуем несколько источников
if wget -q --show-progress -O app/src/main/assets/proot "https://github.com/proot-me/proot-static/releases/download/v5.4.0/proot-arm64"; then
    echo "proot успешно скачан с GitHub"
elif wget -q --show-progress -O app/src/main/assets/proot "https://raw.githubusercontent.com/proot-me/proot-static/master/prebuilt/proot-arm64"; then
    echo "proot скачан с fallback источника"
else
    # Если все источники недоступны, создаём заглушку (для тестов)
    echo "WARNING: Не удалось скачать proot. Создаём заглушку для тестов..."
    echo "#!/system/bin/sh" > app/src/main/assets/proot
    echo "echo 'PROOT PLACEHOLDER'" >> app/src/main/assets/proot
    chmod 755 app/src/main/assets/proot
fi

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
