#!/bin/bash
set -e

# Скрипт сборки настоящего proot для aarch64 через Android NDK
# Результат: libproot.so в app/src/main/jniLibs/arm64-v8a/

# Путь к NDK (GitHub Actions уже его установил)
if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "ANDROID_NDK_HOME не задан!"
    exit 1
fi

# Toolchain NDK
TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
CC=$TOOLCHAIN/bin/aarch64-linux-android34-clang
AR=$TOOLCHAIN/bin/llvm-ar
RANLIB=$TOOLCHAIN/bin/llvm-ranlib
STRIP=$TOOLCHAIN/bin/llvm-strip

# Версии (стабильные)
TALLOC_VERSION=2.4.2
PROOT_VERSION=v5.3.0

# Рабочая папка
WORK_DIR=$PWD/build_proot_tmp
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "=== Скачиваем talloc ==="
curl -L -o talloc.tar.gz https://www.samba.org/ftp/talloc/talloc-${TALLOC_VERSION}.tar.gz
tar xf talloc.tar.gz
cd talloc-${TALLOC_VERSION}

echo "=== Компилируем talloc (статически) ==="
# talloc использует waf (свой build system), ему нужны спец.флаги для cross-compile
cat > cross-answers.txt <<EOF
Checking simple C program: OK
Checking for header endian.h: OK
Checking for header sys/endian.h: OK
Checking for header sys/select.h: OK
Checking for header stdint.h: OK
Checking for header inttypes.h: OK
EOF

CC="$CC" AR="$AR" RANLIB="$RANLIB" \
CFLAGS="-O2 -fPIC --target=aarch64-linux-android34" \
LDFLAGS="--target=aarch64-linux-android34" \
./configure --cross-compile --cross-answers=cross-answers.txt --prefix=$WORK_DIR/talloc_install --disable-python

make -j$(nproc)
make install

TALLOC_DIR=$WORK_DIR/talloc_install
cd $WORK_DIR

echo "=== Скачиваем proot ==="
git clone --depth 1 --branch $PROOT_VERSION https://github.com/proot-me/proot.git
cd proot/src

echo "=== Компилируем proot ==="
# У proot свой Makefile, передаём все нужные переменные
make -j$(nproc) \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    CFLAGS="-O2 --target=aarch64-linux-android34 -I$TALLOC_DIR/include -DARG_MAX=131072" \
    LDFLAGS="--target=aarch64-linux-android34 -L$TALLOC_DIR/lib -ltalloc" \
    VERSION=$PROOT_VERSION \
    proot

#Strip для уменьшения размера
$STRIP proot

echo "=== Копируем в проект как .so ==="
DEST_DIR=../../../app/src/main/jniLibs/arm64-v8a
mkdir -p $DEST_DIR
cp proot $DEST_DIR/libproot.so

echo "=== Готово! Размер libproot.so: ==="
ls -lh $DEST_DIR/libproot.so

# Чистим
cd ../../..
rm -rf build_proot_tmp
