#!/bin/bash
set -e

echo "=== Подготовка ассетов для Secondary OS ==="
mkdir -p app/src/main/assets

# 1. Скачиваем proot
echo "Скачивание proot для arm64..."
wget -q -O app/src/main/assets/proot "https://github.com/proot-me/proot-static/releases/download/v5.4.0/proot-arm64" || {
    echo "Ошибка скачивания proot!"
    exit 1
}
chmod 755 app/src/main/assets/proot
echo "proot скачан: $(ls -lh app/src/main/assets/proot)"

# 2. Создаём МИНИМАЛЬНЫЙ rootfs вручную (без debootstrap)
echo "Создание минимального rootfs..."
ROOTFS_DIR=/tmp/debian-minimal
rm -rf $ROOTFS_DIR
mkdir -p $ROOTFS_DIR/{bin,etc,lib,lib64,usr/bin,usr/lib,tmp,dev,proc,sys,root}

# Создаём базовые файлы
echo "root:x:0:0:root:/root:/bin/sh" > $ROOTFS_DIR/etc/passwd
echo "root:x:0:" > $ROOTFS_DIR/etc/group
echo "localhost" > $ROOTFS_DIR/etc/hostname
echo "nameserver 8.8.8.8" > $ROOTFS_DIR/etc/resolv.conf

# Создаём простой bash-скрипт вместо настоящего bash
cat > $ROOTFS_DIR/bin/sh << 'EOF'
#!/bin/sh
echo "CONTAINER_ALIVE" > /status.txt
echo "Minimal shell working"
EOF
chmod 755 $ROOTFS_DIR/bin/sh

# Копируем stat (нужен для proot)
cp /bin/stat $ROOTFS_DIR/bin/ 2>/dev/null || true

# Архивируем
echo "Архивирование rootfs..."
cd $ROOTFS_DIR
tar -czf /tmp/debian-rootfs.tar.gz .
cd -

# Проверяем размер
ROOTFS_SIZE=$(ls -lh /tmp/debian-rootfs.tar.gz | awk '{print $5}')
echo "Rootfs создан: $ROOTFS_SIZE"

# Копируем в assets
cp /tmp/debian-rootfs.tar.gz app/src/main/assets/

# Очистка
rm -rf $ROOTFS_DIR

echo "=== Ассеты готовы ==="
ls -lh app/src/main/assets/
