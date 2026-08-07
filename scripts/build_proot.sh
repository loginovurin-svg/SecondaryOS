#!/bin/bash
set -e

# Сборка настоящего proot для aarch64 через Android NDK
# Зависимость: talloc (память), собираем первым

# Путь к NDK
if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "ANDROID_NDK_HOME не задан!"
    exit 1
fi

TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
CC=$TOOLCHAIN/bin/aarch64-linux-android34-clang
AR=$TOOLCHAIN/bin/llvm-ar
RANLIB=$TOOLCHAIN/bin/llvm-ranlib
STRIP=$TOOLCHAIN/bin/llvm-strip

TALLOC_VERSION=2.4.2
PROOT_VERSION=v5.3.0

WORK_DIR=$PWD/build_proot_tmp
mkdir -p $WORK_DIR
cd $WORK_DIR

# ============================================================
echo "=== Скачиваем talloc ==="
# ============================================================
curl -L -o talloc.tar.gz https://www.samba.org/ftp/talloc/talloc-${TALLOC_VERSION}.tar.gz
tar xf talloc.tar.gz
cd talloc-${TALLOC_VERSION}

# ============================================================
echo "=== Компилируем talloc ==="
# ============================================================
# Полный cross-answers.txt — ответы на ВСЕ проверки,
# которые требуют запуска программы (невозможно при cross-compile)
cat > cross-answers.txt <<'ENDANSWERS'
Checking uname sysname type: "Linux"
Checking uname machine type: "aarch64"
Checking uname release type: "5.15.0-android"
Checking uname version type: "#1 SMP PREEMPT"
Checking for rpath library support: NO
Checking for -Wl,--version-script support: YES
Checking getconf LFS_CFLAGS: NO
Checking for large file support without additional flags: YES
Checking for -D_FILE_OFFSET_BITS=64: NO
Checking for -D_LARGE_FILES: NO
Checking for library constructor support: YES
Checking for library destructor support: YES
Checking for __attribute__: YES
Checking for HAVE_VISIBILITY_ATTR: YES
Checking for inline: inline
Checking simple C program: OK
Checking for header endian.h: YES
Checking for header sys/endian.h: YES
Checking for header sys/select.h: YES
Checking for header stdint.h: YES
Checking for header inttypes.h: YES
Checking for header sys/utsname.h: YES
Checking for header sys/types.h: YES
Checking for header sys/stat.h: YES
Checking for header stdlib.h: YES
Checking for header stddef.h: YES
Checking for header memory.h: YES
Checking for header string.h: YES
Checking for header strings.h: YES
Checking for header unistd.h: YES
Checking for header ctype.h: YES
Checking for header stdbool.h: YES
Checking for header stdarg.h: YES
Checking for header limits.h: YES
Checking for header assert.h: YES
ENDANSWERS

CC="$CC" AR="$AR" RANLIB="$RANLIB" \
CFLAGS="-O2 -fPIC --target=aarch64-linux-android34 -D_FILE_OFFSET_BITS=64" \
LDFLAGS="--target=aarch64-linux-android34" \
./configure \
    --cross-compile \
    --cross-answers=$PWD/cross-answers.txt \
    --prefix=$WORK_DIR/talloc_install \
    --disable-python

make -j$(nproc)
make install

TALLOC_DIR=$WORK_DIR/talloc_install
cd $WORK_DIR

# ============================================================
echo "=== Скачиваем proot ==="
# ============================================================
git clone --depth 1 --branch $PROOT_VERSION https://github.com/proot-me/proot.git
cd proot/src

# ============================================================
echo "=== Компилируем proot ==="
# ============================================================
make -j$(nproc) \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    CFLAGS="-O2 --target=aarch64-linux-android34 -I$TALLOC_DIR/include -D_FILE_OFFSET_BITS=64 -DARG_MAX=131072" \
    LDFLAGS="--target=aarch64-linux-android34 -L$TALLOC_DIR/lib -ltalloc" \
    VERSION=$PROOT_VERSION \
    proot

$STRIP proot

# ============================================================
echo "=== Копируем в проект как .so ==="
# ============================================================
DEST_DIR=../../../app/src/main/jniLibs/arm64-v8a
mkdir -p $DEST_DIR
cp proot $DEST_DIR/libproot.so

echo "=== Готово! Размер libproot.so: ==="
ls -lh $DEST_DIR/libproot.so

cd ../../..
rm -rf build_proot_tmp
