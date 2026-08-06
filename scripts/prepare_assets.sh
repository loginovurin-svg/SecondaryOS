#!/bin/bash
set -e

echo "=== Подготовка ассетов для Secondary OS ==="

# 1. Устанавливаем кросс-компилятор для aarch64
echo "Установка aarch64 cross-compiler..."
sudo apt-get update -qq
sudo apt-get install -y -qq gcc-aarch64-linux-gnu libc6-dev-arm64-cross

# 2. Создаём папку для нативной библиотеки
mkdir -p app/src/main/jniLibs/arm64-v8a

# 3. Компилируем stub_proot как статический ELF aarch64
echo "Компиляция stub_proot (ELF aarch64, static)..."
aarch64-linux-gnu-gcc -static -O2 -o app/src/main/jniLibs/arm64-v8a/libproot.so scripts/stub_proot.c
chmod 755 app/src/main/jniLibs/arm64-v8a/libproot.so

# Проверяем, что это ELF
file app/src/main/jniLibs/arm64-v8a/libproot.so
ls -lh app/src/main/jniLibs/arm64-v8a/libproot.so

# 4. Создаём минимальный rootfs
echo "Создание минимального rootfs..."
ROOTFS_DIR=/tmp/debian-minimal
rm -rf $ROOTFS_DIR
mkdir -p $ROOTFS_DIR/{bin,etc,lib,usr/bin,tmp,dev,proc,sys,root}

echo "root:x:0:0:root:/root:/bin/sh" > $ROOTFS_DIR/etc/passwd
echo "root:x:0:" > $ROOTFS_DIR/etc/group
echo "localhost" > $ROOTFS_DIR/etc/hostname
echo "nameserver 8.8.8.8" > $ROOTFS_DIR/etc/resolv.conf

cat > $ROOTFS_DIR/bin/sh << 'SHELL_EOF'
#!/bin/sh
echo "CONTAINER_ALIVE" > /status.txt
echo "Minimal shell working"
SHELL_EOF
chmod 755 $ROOTFS_DIR/bin/sh

echo "Архивирование rootfs..."
cd $ROOTFS_DIR
tar -czf /tmp/debian-rootfs.tar.gz .
cd -

# Копируем rootfs в assets (proot больше не нужен в assets!)
mkdir -p app/src/main/assets
cp /tmp/debian-rootfs.tar.gz app/src/main/assets/
ROOTFS_SIZE=$(ls -lh app/src/main/assets/debian-rootfs.tar.gz | awk '{print $5}')
echo "✓ Rootfs создан: $ROOTFS_SIZE"

rm -rf $ROOTFS_DIR

echo "=== Ассеты готовы ==="
ls -lh app/src/main/assets/
ls -lh app/src/main/jniLibs/arm64-v8a/
