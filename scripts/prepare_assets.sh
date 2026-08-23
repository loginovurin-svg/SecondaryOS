#!/bin/bash
# scripts/prepare_assets.sh
# Собирает QEMU user-mode из исходников для ARM64 и скачивает Debian rootfs

set -e

# Получаем абсолютный путь к корню проекта
PROJECT_ROOT="$(pwd)"
ASSETS_DIR="$PROJECT_ROOT/app/src/main/assets"
mkdir -p "$ASSETS_DIR"

echo "=== 1. Сборка qemu-aarch64 из исходников ==="
QEMU_BIN="$ASSETS_DIR/qemu-aarch64"

if [ ! -f "$QEMU_BIN" ]; then
    echo "Скачивание исходников QEMU..."
    
    # Стабильная версия QEMU
    QEMU_VERSION="8.2.4"
    QEMU_SRC="qemu-${QEMU_VERSION}.tar.xz"
    QEMU_URL="https://download.qemu.org/${QEMU_SRC}"
    
    curl -L --fail -o "$ASSETS_DIR/$QEMU_SRC" "$QEMU_URL" || {
        echo "❌ Не удалось скачать QEMU"
        exit 1
    }
    
    echo "Распаковка исходников..."
    cd "$ASSETS_DIR"
    tar -xf "$QEMU_SRC"
    rm "$QEMU_SRC"
    
    echo "Настройка и компиляция QEMU user-mode (это займёт 5-10 минут)..."
    cd "qemu-${QEMU_VERSION}"
    
    # Устанавливаем префикс в локальную директорию, доступную для записи без sudo
    INSTALL_DIR="$(pwd)/qemu-install"
    
    # Конфигурируем только user-mode эмуляцию для aarch64
    ./configure \
        --target-list=aarch64-linux-user \
        --static \
        --disable-system \
        --disable-tools \
        --disable-docs \
        --disable-pie \
        --prefix="$INSTALL_DIR" || {
        echo "❌ Ошибка конфигурации QEMU"
        cd "$PROJECT_ROOT"
        exit 1
    }
    
    echo "Компиляция (используем все доступные ядра)..."
    make -j$(nproc) || {
        echo "❌ Ошибка компиляции QEMU"
        cd "$PROJECT_ROOT"
        exit 1
    }
    
    echo "Установка в локальную директорию (без sudo)..."
    make install
    
    # Копируем готовый статический бинарник в нужное место
    # Используем абсолютный путь для ASSETS_DIR
    cp "$INSTALL_DIR/bin/qemu-aarch64" "$ASSETS_DIR/qemu-aarch64"
    chmod +x "$ASSETS_DIR/qemu-aarch64"
    
    # Возвращаемся в корень проекта
    cd "$PROJECT_ROOT"
    
    # Очистка исходников и временной директории установки (экономим место в репозитории)
    rm -rf "$ASSETS_DIR/qemu-${QEMU_VERSION}"
    
    # Проверка архитектуры
    if file "$QEMU_BIN" | grep -q "aarch64\|ARM64"; then
        echo "✅ qemu-aarch64 собран (ARM64, статический)."
        file "$QEMU_BIN"
    else
        echo "️ ВНИМАНИЕ: файл может быть не для ARM64"
        file "$QEMU_BIN"
    fi
    
    # Показываем размер
    SIZE=$(stat -c%s "$QEMU_BIN" 2>/dev/null || stat -f%z "$QEMU_BIN")
    echo "  Размер бинарника: $((SIZE / 1024 / 1024)) МБ"
    
else
    echo "qemu-aarch64 уже существует, пропускаем сборку."
fi

echo "=== 2. Скачивание Debian 11 rootfs ==="
ROOTFS_ARCHIVE="$ASSETS_DIR/debian-rootfs.tar.xz"

if [ ! -f "$ROOTFS_ARCHIVE" ]; then
    echo "Скачивание Debian rootfs (это займёт время, ~180-200 МБ)..."
    
    # Официальный Debian cloud image nocloud (минимальный, без лишних сервисов)
    ROOTFS_URL="https://cdimage.debian.org/cdimage/cloud/bullseye/latest/debian-11-nocloud-arm64.tar.xz"
    
    if ! curl -L --fail -o "$ROOTFS_ARCHIVE" "$ROOTFS_URL"; then
        echo "❌ Официальный Debian недоступен."
        rm -f "$ROOTFS_ARCHIVE"
        exit 1
    fi
    
    # Проверка размера (должно быть > 100 МБ)
    FILE_SIZE=$(stat -c%s "$ROOTFS_ARCHIVE" 2>/dev/null || stat -f%z "$ROOTFS_ARCHIVE")
    if [ "$FILE_SIZE" -lt 100000000 ]; then
        echo "❌ Файл слишком мал ($FILE_SIZE байт). Ссылка устарела."
        rm -f "$ROOTFS_ARCHIVE"
        exit 1
    fi
    echo "✅ Debian rootfs загружен (Размер: $((FILE_SIZE / 1024 / 1024)) МБ)."
else
    echo "Debian rootfs уже существует, пропускаем."
fi

echo "=== 3. Очистка старых артефактов ==="
rm -f "$ASSETS_DIR/proot" "$ASSETS_DIR/busybox" "$ASSETS_DIR/toybox" "$ASSETS_DIR/qemu.deb"

echo "=== Итог ==="
echo "Файлы в assets:"
ls -lh "$ASSETS_DIR/"
echo ""
echo "✅ Assets готовы. APK будет включать:"
echo "  - qemu-aarch64 (собранный из исходников, ARM64, статический)"
echo "  - debian-rootfs.tar.xz (официальный образ Debian 11)"
echo ""
echo "⚠️ Размер APK будет около 200-250 МБ."
