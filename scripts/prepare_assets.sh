#!/bin/bash
set -e

echo "=== Подготовка ассетов для Secondary OS ==="

# 1. Устанавливаем NDK
echo "Установка Android NDK..."
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager "ndk;26.1.10909125"

NDK_PATH=$ANDROID_HOME/ndk/26.1.10909125
TOOLCHAIN=$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64

# 2. Создаём папку для нативной библиотеки
mkdir -p app/src/main/jniLibs/arm64-v8a

# 3. Компилируем stub_proot через NDK clang (bionic libc — совместима с Android 16)
echo "Компиляция stub_proot через NDK..."
$TOOLCHAIN/bin/aarch64-linux-android34-clang \
    -O2 \
    -o app/src/main/jniLibs/arm64-v8a/libproot.so \
    scripts/stub_proot.c

chmod 755 app/src/main/jniLibs/arm64-v8a/libproot.so

# Проверяем
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

mkdir -p app/src/main/assets
cp /tmp/debian-rootfs.tar.gz app/src/main/assets/
ROOTFS_SIZE=$(ls -lh app/src/main/assets/debian-rootfs.tar.gz | awk '{print $5}')
echo "✓ Rootfs создан: $ROOTFS_SIZE"

rm -rf $ROOTFS_DIR

echo "=== Ассеты готовы ==="
ls -lh app/src/main/assets/
ls -lh app/src/main/jniLibs/arm64-v8a/
