#!/bin/bash
set -e

# ============================================================
# Сборка настоящего proot для aarch64 через Android NDK
# Использует qemu-user-static для runtime-проверок waf
# Результат: app/src/main/jniLibs/arm64-v8a/libproot.so
# ============================================================

if [ -z "$ANDROID_NDK_HOME" ]; then
    export ANDROID_NDK_HOME=$(ls -d /usr/local/lib/android/sdk/ndk/* 2>/dev/null | head -1)
    if [ -z "$ANDROID_NDK_HOME" ]; then
        echo "ОШИБКА: ANDROID_NDK_HOME не задан!"
        exit 1
    fi
fi
echo "Используем NDK: $ANDROID_NDK_HOME"

TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
SYSROOT=$TOOLCHAIN/sysroot
CC=$TOOLCHAIN/bin/aarch64-linux-android34-clang
AR=$TOOLCHAIN/bin/llvm-ar
RANLIB=$TOOLCHAIN/bin/llvm-ranlib
STRIP=$TOOLCHAIN/bin/llvm-strip

TALLOC_VERSION=2.4.2
PROOT_VERSION=v5.3.0

WORK_DIR=$PWD/build_proot_tmp
rm -rf $WORK_DIR
mkdir -p $WORK_DIR

# ============================================================
# ШАГ 0: Устанавливаем qemu для запуска aarch64 бинарников
# ============================================================
echo ""
echo "=========================================="
echo "=== ШАГ 0: Настраиваем qemu-aarch64 ==="
echo "=========================================="

if ! command -v qemu-aarch64-static &> /dev/null; then
    echo "Устанавливаем qemu-user-static..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq qemu-user-static
fi
echo "qemu-aarch64-static: $(qemu-aarch64-static --version 2>&1 | head -1)"

# Bionic ищет библиотеки по хардкод-путям /system/lib64/
# Создаём symlink'и в sysroot NDK, чтобы qemu нашёл bionic
mkdir -p $SYSROOT/system/lib64
mkdir -p $SYSROOT/system/bin

for lib in libc.so libm.so libdl.so liblog.so; do
    src=$(find $SYSROOT/usr/lib/aarch64-linux-android -maxdepth 2 -name "$lib" 2>/dev/null | head -1)
    if [ -n "$src" ] && [ ! -e $SYSROOT/system/lib64/$lib ]; then
        ln -sf "$src" $SYSROOT/system/lib64/$lib
        echo "  symlink: $lib -> $src"
    fi
done

# Линковщик bionic
ld_src=$(find $SYSROOT/usr/lib/aarch64-linux-android -maxdepth 2 -name "ld-android.so" 2>/dev/null | head -1)
if [ -n "$ld_src" ] && [ ! -e $SYSROOT/system/bin/linker64 ]; then
    ln -sf "$ld_src" $SYSROOT/system/bin/linker64
    echo "  symlink: linker64 -> $ld_src"
fi

# Проверяем что qemu может запустить простой aarch64 бинарник
echo "Тестируем qemu..."
cat > $WORK_DIR/test_qemu.c <<'EOF'
#include <stdio.h>
int main() { printf("qemu works\n"); return 0; }
EOF
$CC --target=aarch64-linux-android34 -o $WORK_DIR/test_qemu $WORK_DIR/test_qemu.c
QEMU_OUT=$(qemu-aarch64-static -L $SYSROOT $WORK_DIR/test_qemu 2>&1) || true
echo "  qemu test: $QEMU_OUT"

cd $WORK_DIR

# ============================================================
# ШАГ 1: Скачиваем и собираем talloc
# ============================================================
echo ""
echo "=========================================="
echo "=== ШАГ 1: Скачиваем talloc $TALLOC_VERSION ==="
echo "=========================================="
curl -L -o talloc.tar.gz "https://www.samba.org/ftp/talloc/talloc-${TALLOC_VERSION}.tar.gz"
tar xf talloc.tar.gz
cd talloc-${TALLOC_VERSION}

echo "=== Компилируем talloc (через qemu cross-execute) ==="

# КЛЮЧЕВОЙ МОМЕНТ: --cross-execute заставляет waf запускать
# тестовые программы через qemu. cross-answers.txt НЕ НУЖЕН!
CC="$CC" AR="$AR" RANLIB="$RANLIB" \
CFLAGS="-O2 -fPIC --target=aarch64-linux-android34 -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE" \
LDFLAGS="--target=aarch64-linux-android34" \
./configure \
    --cross-compile \
    --cross-execute="qemu-aarch64-static -L $SYSROOT" \
    --prefix=$WORK_DIR/talloc_install \
    --disable-python \
    --disable-rpath-install

make -j$(nproc)
make install

TALLOC_DIR=$WORK_DIR/talloc_install
echo "=== talloc собран! ==="
ls -la $TALLOC_DIR/lib/

cd $WORK_DIR

# ============================================================
# ШАГ 2: Скачиваем и собираем proot
# ============================================================
echo ""
echo "=========================================="
echo "=== ШАГ 2: Скачиваем proot $PROOT_VERSION ==="
echo "=========================================="
git clone --depth 1 --branch $PROOT_VERSION https://github.com/proot-me/proot.git
cd proot/src

echo "=== Компилируем proot ==="
make -j$(nproc) \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    CFLAGS="-O2 --target=aarch64-linux-android34 -I$TALLOC_DIR/include -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -DARG_MAX=131072" \
    LDFLAGS="--target=aarch64-linux-android34 -L$TALLOC_DIR/lib -ltalloc -static" \
    VERSION=$PROOT_VERSION \
    proot

$STRIP proot

echo "=== proot собран! ==="
file proot || true
ls -lh proot

# ============================================================
# ШАГ 3: Копируем в проект
# ============================================================
echo ""
echo "=========================================="
echo "=== ШАГ 3: Копируем в проект ==="
echo "=========================================="
DEST_DIR=$PWD/../../../app/src/main/jniLibs/arm64-v8a
mkdir -p $DEST_DIR
cp proot $DEST_DIR/libproot.so

echo "=== Готово! ==="
ls -lh $DEST_DIR/libproot.so

cd ../../..
rm -rf build_proot_tmp

echo ""
echo "=== Сборка proot завершена успешно ==="
