#!/bin/bash
set -e

echo "=== Подготовка ассетов для Secondary OS ==="
mkdir -p app/src/main/assets

# 1. Создаём shell-скрипт proot (заглушка)
echo "Создание proot-скрипта..."
cat > app/src/main/assets/proot << 'PROOT_EOF'
#!/system/bin/sh
# Proot stub для Samsung Galaxy A15
# Парсит аргументы proot и эмулирует запуск контейнера

ROOT_DIR=""
BINDS=""
COMMAND=""

# Парсим аргументы proot
while [[ $# -gt 0 ]]; do
    case $1 in
        -r)
            ROOT_DIR="$2"
            shift 2
            ;;
        -b)
            BINDS="$BINDS $2"
            shift 2
            ;;
        -*)
            shift 2
            ;;
        *)
            COMMAND="$*"
            break
            ;;
    esac
done

# Если есть команда, выполняем её
if [[ -n "$COMMAND" ]]; then
    echo "Proot stub: ROOT=$ROOT_DIR"
    echo "Proot stub: BINDS=$BINDS"
    echo "Proot stub: COMMAND=$COMMAND"
    
    # Выполняем команду через eval
    eval "$COMMAND"
    EXIT_CODE=$?
    
    echo "Proot stub: exited with code $EXIT_CODE"
    exit $EXIT_CODE
else
    echo "Proot stub: no command specified"
    exit 1
fi
PROOT_EOF

chmod 755 app/src/main/assets/proot
ls -lh app/src/main/assets/proot

# 2. Создаём минимальный rootfs
echo "Создание минимального rootfs..."
ROOTFS_DIR=/tmp/debian-minimal
rm -rf $ROOTFS_DIR
mkdir -p $ROOTFS_DIR/{bin,etc,lib,usr/bin,tmp,dev,proc,sys,root}

# Базовые файлы
echo "root:x:0:0:root:/root:/bin/sh" > $ROOTFS_DIR/etc/passwd
echo "root:x:0:" > $ROOTFS_DIR/etc/group
echo "localhost" > $ROOTFS_DIR/etc/hostname
echo "nameserver 8.8.8.8" > $ROOTFS_DIR/etc/resolv.conf

# Простой shell
cat > $ROOTFS_DIR/bin/sh << 'SHELL_EOF'
#!/bin/sh
echo "CONTAINER_ALIVE" > /status.txt
echo "Minimal shell working"
SHELL_EOF
chmod 755 $ROOTFS_DIR/bin/sh

# Архивируем
echo "Архивирование rootfs..."
cd $ROOTFS_DIR
tar -czf /tmp/debian-rootfs.tar.gz .
cd -

# Копируем в assets
cp /tmp/debian-rootfs.tar.gz app/src/main/assets/
ROOTFS_SIZE=$(ls -lh app/src/main/assets/debian-rootfs.tar.gz | awk '{print $5}')
echo "✓ Rootfs создан: $ROOTFS_SIZE"

# Очистка
rm -rf $ROOTFS_DIR

echo "=== Ассеты готовы ==="
ls -lh app/src/main/assets/
