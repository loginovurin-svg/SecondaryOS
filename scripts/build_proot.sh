#!/bin/bash
set -e

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

echo ""
echo "=========================================="
echo "=== ШАГ 0: Настраиваем qemu-aarch64 ==="
echo "=========================================="

if ! command -v qemu-aarch64-static &> /dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq qemu-user-static
fi
echo "qemu-aarch64-static: $(qemu-aarch64-static --version 2>&1 | head -1)"

mkdir -p $SYSROOT/system/lib64
mkdir -p $SYSROOT/system/bin

for lib in libc.so libm.so libdl.so liblog.so; do
    src=$(find $SYSROOT/usr/lib/aarch64-linux-android -name "$lib" 2>/dev/null | head -1)
    if [ -n "$src" ] && [ ! -e $SYSROOT/system/lib64/$lib ]; then
        ln -sf "$src" $SYSROOT/system/lib64/$lib
        echo "  symlink: $lib"
    fi
done

ld_src=$(find $SYSROOT/usr/lib/aarch64-linux-android -name "ld-android.so" 2>/dev/null | head -1)
if [ -z "$ld_src" ]; then
    echo "ld-android.so не найден, используем статическую линковку"
    USE_STATIC=1
else
    if [ ! -e $SYSROOT/system/bin/linker64 ]; then
        ln -sf "$ld_src" $SYSROOT/system/bin/linker64
    fi
    USE_STATIC=0
fi

cat > $WORK_DIR/test_qemu.c <<'EOF'
#include <stdio.h>
int main() { printf("qemu works\n"); return 0; }
EOF

if [ "$USE_STATIC" = "1" ]; then
    $CC --target=aarch64-linux-android34 -static -o $WORK_DIR/test_qemu $WORK_DIR/test_qemu.c
    QEMU_OUT=$(qemu-aarch64-static $WORK_DIR/test_qemu 2>&1) || true
else
    $CC --target=aarch64-linux-android34 -o $WORK_DIR/test_qemu $WORK_DIR/test_qemu.c
    QEMU_OUT=$(qemu-aarch64-static -L $SYSROOT $WORK_DIR/test_qemu 2>&1) || true
fi
echo "  qemu test: $QEMU_OUT"

if echo "$QEMU_OUT" | grep -q "qemu works"; then
    echo "  ✓ qemu работает!"
    if [ "$USE_STATIC" = "0" ]; then
        CROSS_EXECUTE_CMD="qemu-aarch64-static -L $SYSROOT"
    else
        CROSS_EXECUTE_CMD="qemu-aarch64-static"
    fi
else
    echo "  ✗ qemu не работает, используем cross-answers.txt"
    CROSS_EXECUTE_CMD=""
fi

cd $WORK_DIR

echo ""
echo "=========================================="
echo "=== ШАГ 1: Скачиваем talloc $TALLOC_VERSION ==="
echo "=========================================="
curl -L -o talloc.tar.gz "https://www.samba.org/ftp/talloc/talloc-${TALLOC_VERSION}.tar.gz"
tar xf talloc.tar.gz
cd talloc-${TALLOC_VERSION}

echo "=== Компилируем talloc ==="

CFLAGS="-O2 -fPIC --target=aarch64-linux-android34 -D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE"
LDFLAGS="--target=aarch64-linux-android34"

if [ -n "$CROSS_EXECUTE_CMD" ]; then
    echo "Режим: qemu cross-execute"
    if [ "$USE_STATIC" = "1" ]; then
        CFLAGS="$CFLAGS -static"
        LDFLAGS="$LDFLAGS -static"
    fi
    
    # КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ: передаём --cross-execute напрямую, без кавычек в переменной
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    ./configure \
        --cross-compile \
        --cross-execute="$CROSS_EXECUTE_CMD" \
        --prefix=$WORK_DIR/talloc_install \
        --disable-python \
        --disable-rpath-install
else
    echo "Режим: cross-answers.txt"
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
Checking if signal handlers return int: YES
Checking correct behavior of strtoll: YES
Checking for working strptime: YES
Checking for C99 vsnprintf: YES
Checking for HAVE_SHARED_MMAP: YES
Checking for HAVE_MREMAP: YES
Checking for HAVE_INCOHERENT_MMAP: NO
Checking for HAVE_SECURE_MKSTEMP: YES
Checking for HAVE_IMMEDIATE_STRUCTURES: OK
Checking for HAVE_MKDIR_MODE: OK
Checking for HAVE_UNIXSOCKET: OK
Checking for HAVE_LITTLE_ENDIAN: OK
Checking for HAVE_BIG_ENDIAN: NO
Checking for HAVE_IPV6: OK
Checking whether we have ucontext_t: OK
Checking whether xattr interface takes additional options: NO
Checking for comparison_fn_t: NO
Checking C prototype for gettimeofday: OK
Checking C prototype for dlopen: OK
Checking simple C program: OK
Checking for library constructor support: OK
Checking for library destructor support: OK
Checking for __attribute__: OK
Checking for HAVE_VISIBILITY_ATTR: OK
Checking for inline: inline
Checking for prctl syscall: OK
Checking for O_DIRECT flag to open(2): OK
Checking for long long: OK
Checking for intptr_t: OK
Checking for uintptr_t: OK
Checking for ptrdiff_t: OK
Checking for bool: OK
Checking for volatile int: OK
Checking for socklen_t: OK
Checking for sig_atomic_t: OK
Checking for sa_family_t: OK
Checking for inotify_init: OK
Checking for epoll_create1: OK
Checking for eventfd: OK
Checking for poll: OK
Checking for mmap: OK
Checking for syscall: OK
Checking for getpagesize: OK
Checking for dlopen: OK
Checking for dlsym: OK
Checking for dlerror: OK
Checking for dlclose: OK
Checking for fdatasync: OK
Checking for clock_gettime: OK
Checking whether the clock_gettime clock ID CLOCK_MONOTONIC is available: OK
Checking whether the clock_gettime clock ID CLOCK_PROCESS_CPUTIME_ID is available: OK
Checking whether the clock_gettime clock ID CLOCK_REALTIME is available: OK
Checking for pthread_create: OK
Checking for pthread_attr_init: OK
Checking for __thread local storage: OK
Checking for __sync_fetch_and_add compiler builtin: OK
Checking for __sync_add_and_fetch compiler builtin: OK
Checking for __atomic_add_fetch compiler builtin: OK
Checking for __atomic_load compiler builtin: OK
Checking for atomic_thread_fence(memory_order_seq_cst) in stdatomic.h: OK
Checking for fallthrough attribute: OK
Checking for memset_explicit: OK
Checking for volatile memory protection: OK
Checking whether we can use SO_PEERCRED to get socket credentials: OK
Checking for posix_fallocate-capable libc: OK
Checking for posix_fallocate: OK
Checking for struct ifaddrs: OK
Checking for struct addrinfo: OK
Checking for struct sockaddr: OK
Checking for HAVE_STRUCT_SOCKADDR_IN6: OK
Checking for struct sockaddr_storage: OK
Checking for sigsetmask: OK
Checking for sigprocmask: OK
Checking for sigblock: OK
Checking for sigaction: OK
Checking for sigset: OK
Checking for inet_ntoa: OK
Checking for inet_aton: OK
Checking for inet_ntop: OK
Checking for inet_pton: OK
Checking for connect: OK
Checking for gethostbyname: OK
Checking for getaddrinfo: OK
Checking for getnameinfo: OK
Checking for freeaddrinfo: OK
Checking for gai_strerror: OK
Checking for socketpair: OK
Checking for variable IPV6_V6ONLY: OK
Checking for strdup: OK
Checking for memmem: OK
Checking for printf: OK
Checking for memset: OK
Checking for memcpy: OK
Checking for memmove: OK
Checking for strcpy: OK
Checking for strncpy: OK
Checking for bzero: OK
Checking for pipe: OK
Checking for strftime: OK
Checking for srandom: OK
Checking for random: OK
Checking for srand: OK
Checking for rand: OK
Checking for usleep: OK
Checking for setbuffer: OK
Checking for lstat: OK
Checking for getpgrp: OK
Checking for utime: OK
Checking for utimes: OK
Checking for setuid: OK
Checking for seteuid: OK
Checking for setreuid: OK
Checking for setresuid: OK
Checking for setgid: OK
Checking for setegid: OK
Checking for setregid: OK
Checking for setresgid: OK
Checking for chroot: OK
Checking for strerror: OK
Checking for vsyslog: OK
Checking for setlinebuf: OK
Checking for mktime: OK
Checking for ftruncate: OK
Checking for rename: OK
Checking for waitpid: OK
Checking for wait4: OK
Checking for initgroups: OK
Checking for pread: OK
Checking for pwrite: OK
Checking for strndup: OK
Checking for strcasestr: OK
Checking for strsep: OK
Checking for strtok_r: OK
Checking for mkdtemp: OK
Checking for dup2: OK
Checking for dprintf: OK
Checking for vdprintf: OK
Checking for isatty: OK
Checking for chown: OK
Checking for lchown: OK
Checking for link: OK
Checking for readlink: OK
Checking for symlink: OK
Checking for realpath: OK
Checking for snprintf: OK
Checking for vsnprintf: OK
Checking for asprintf: OK
Checking for vasprintf: OK
Checking for setenv: OK
Checking for unsetenv: OK
Checking for strnlen: OK
Checking for strtoull: OK
Checking for strtoll: OK
Checking for memalign: OK
Checking for posix_memalign: OK
Checking for fmemopen: OK
Checking for prctl: OK
Checking for dirname: OK
Checking for basename: OK
Checking for strlcpy: OK
Checking for strlcat: OK
Checking for if_nameindex: OK
Checking for if_nametoindex: OK
Checking for strerror_r: OK
Checking for syslog: OK
Checking for timegm: OK
Checking for getifaddrs: OK
Checking for freeifaddrs: OK
Checking for setgroups: OK
Checking for setsid: OK
Checking for getgrgid_r: OK
Checking for getgrnam_r: OK
Checking for getgrouplist: OK
Checking for getpwnam_r: OK
Checking for getpwuid_r: OK
Checking for copy_file_range: OK
Checking for getxattr: OK
Checking for getauxval: OK
Checking for declaration of dlopen: OK
Checking for declaration of fdatasync: OK
Checking for declaration of snprintf: OK
Checking for declaration of vsnprintf: OK
Checking for declaration of asprintf: OK
Checking for declaration of vasprintf: OK
Checking for declaration of errno: OK
Checking for declaration of EWOULDBLOCK: OK
Checking for declaration of environ: OK
Checking for declaration of pread: OK
Checking for declaration of pwrite: OK
Checking for declaration of setenv: OK
Checking for declaration of setresgid: OK
Checking for declaration of setresuid: OK
Checking for declaration of memalign: OK
Checking for declaration of strptime: OK
Checking for declaration of gettimeofday: OK
Checking for declaration of malloc: OK
Checking for member st_rdev in struct stat: OK
Checking for member ss_family in struct sockaddr_storage: OK
Checking for getprogname: OK
Checking for variable __FUNCTION__: OK
Checking for va_copy: OK
Checking for HAVE_IFACE_GETIFADDRS: YES
Checking for HAVE_IFACE_AIX: NO
Checking for HAVE_IFACE_IFCONF: YES
Checking for HAVE_IFACE_IFREQ: YES
Checking for XSI (rather than GNU) prototype for strerror_r: NO
Checking for header sys/utsname.h: YES
Checking for header stdio.h: YES
Checking for header sys/types.h: YES
Checking for header sys/stat.h: YES
Checking for header stdlib.h: YES
Checking for header stddef.h: YES
Checking for header memory.h: YES
Checking for header string.h: YES
Checking for header strings.h: YES
Checking for header inttypes.h: YES
Checking for header stdint.h: YES
Checking for header unistd.h: YES
Checking for header ctype.h: YES
Checking for header stdbool.h: YES
Checking for header stdarg.h: YES
Checking for header limits.h: YES
Checking for header assert.h: YES
Checking for header endian.h: YES
Checking for header sys/endian.h: YES
Checking for header sys/select.h: YES
Checking for header sys/time.h: YES
Checking for header time.h: YES
Checking for header signal.h: YES
Checking for header linux/types.h: YES
Checking for header locale.h: YES
Checking for header fcntl.h: YES
Checking for header fnmatch.h: YES
Checking for header glob.h: YES
Checking for header langinfo.h: YES
Checking for header pwd.h: YES
Checking for header sys/capability.h: YES
Checking for header sys/epoll.h: YES
Checking for header sys/fcntl.h: YES
Checking for header sys/ioctl.h: YES
Checking for header sys/ipc.h: YES
Checking for header sys/mman.h: YES
Checking for header sys/resource.h: YES
Checking for header sys/shm.h: YES
Checking for header sys/statfs.h: YES
Checking for header sys/statvfs.h: YES
Checking for header sys/vfs.h: YES
Checking for header sys/xattr.h: YES
Checking for header termio.h: YES
Checking for header termios.h: YES
Checking for header sys/file.h: YES
Checking for header sys/ucontext.h: YES
Checking for header sys/wait.h: YES
Checking for header grp.h: YES
Checking for header setjmp.h: YES
Checking for header utime.h: YES
Checking for header sys/syslog.h: YES
Checking for header syslog.h: YES
Checking for header sys/mount.h: YES
Checking for header mntent.h: YES
Checking for header sys/param.h: YES
Checking for header sys/socket.h: YES
Checking for header netinet/in.h: YES
Checking for header netdb.h: YES
Checking for header arpa/inet.h: YES
Checking for header netinet/in_systm.h: YES
Checking for header netinet/ip.h: YES
Checking for header netinet/tcp.h: YES
Checking for header sys/un.h: YES
Checking for header sys/uio.h: YES
Checking for header ifaddrs.h: YES
Checking for header dirent.h: YES
Checking for header errno.h: YES
Checking for header getopt.h: YES
Checking for header iconv.h: YES
Checking for header linux/openat2.h: YES
Checking for header zlib.h: YES
Checking for header asm/unistd.h: YES
Checking for header sys/unistd.h: YES
Checking for header alloca.h: YES
Checking for header float.h: YES
Checking for header sys/sysmacros.h: YES
Checking for header stdatomic.h: YES
Checking for header libgen.h: YES
Checking for header sys/prctl.h: YES
Checking for header malloc.h: YES
Checking for header poll.h: YES
Checking for header utmp.h: YES
Checking for header utmpx.h: YES
Checking for header lastlog.h: YES
Checking for header syscall.h: YES
Checking for header sys/syscall.h: YES
Checking for header sys/cdefs.h: YES
Checking for header net/if.h: YES
Checking for header arpa/nameser.h: YES
Checking for header resolv.h: YES
Checking for header sys/auxv.h: YES
Checking for res_search: OK
Checking for header security/pam_appl.h: NO
Checking for header crypt.h: NO
Checking for header acl/libacl.h: NO
Checking for header compat.h: NO
Checking for header attr/xattr.h: NO
Checking for header dustat.h: NO
Checking for header history.h: NO
Checking for header krb5.h: NO
Checking for header ndir.h: NO
Checking for header shadow.h: NO
Checking for header sys/acl.h: NO
Checking for header sys/attributes.h: NO
Checking for header attr/attributes.h: NO
Checking for header sys/dir.h: NO
Checking for header sys/filio.h: NO
Checking for header sys/filsys.h: NO
Checking for header sys/fs/s5param.h: NO
Checking for header sys/id.h: NO
Checking for header sys/mode.h: NO
Checking for header sys/ndir.h: NO
Checking for header sys/priv.h: NO
Checking for header sys/security.h: NO
Checking for header sys/termio.h: NO
Checking for header stropts.h: NO
Checking for header unix.h: NO
Checking for header netinet/in_ip.h: NO
Checking for header sys/sockio.h: NO
Checking for header direct.h: NO
Checking for header windows.h: NO
Checking for header winsock2.h: NO
Checking for header ws2tcpip.h: NO
Checking for header nss.h: NO
Checking for header sasl/sasl.h: NO
Checking for header sys/sysctl.h: NO
Checking for header sys/fileio.h: NO
Checking for header sys/filesys.h: NO
Checking for header sys/dustat.h: NO
Checking for header xfs/libxfs.h: NO
Checking for header netgroup.h: NO
Checking for header valgrind.h: NO
Checking for header valgrind/valgrind.h: NO
Checking for header valgrind/memcheck.h: NO
Checking for header valgrind/helgrind.h: NO
Checking for header valgrind/callgrind.h: NO
Checking for header nss_common.h: NO
Checking for header nsswitch.h: NO
Checking for header ns_api.h: NO
Checking for header sys/extattr.h: NO
Checking for header sys/ea.h: NO
Checking for header sys/proplist.h: NO
Checking for header sys/atomic.h: NO
Checking for header minix/config.h: NO
Checking for header standards.h: NO
Checking for header vararg.h: NO
Checking for header libintl.h: NO
Checking for header readline.h: NO
Checking for header readline/readline.h: NO
Checking for header readline/history.h: NO
Checking for header rpc/rpc.h: NO
Checking for header rpc/nettype.h: NO
Checking for tirpc rpc headers in default system path: NO
Checking for libtirpc headers: NO
Checking for libntirpc headers: NO
Checking for library intl: NO
Checking for library bsd: NO
Checking for library pthread: NO
Checking for library crypt: NO
Checking for library setproctitle: NO
Checking for getpeereid: NO
Checking for setproctitle: NO
Checking for setproctitle_init: NO
Checking for closefrom: NO
Checking for crypt: NO
Checking for crypt_r: NO
Checking for crypt_rn: NO
Checking for pthread_mutexattr_setrobust: NO
Checking for pthread_mutexattr_setrobust_np: NO
Checking for pthread_mutex_consistent: NO
Checking for pthread_mutex_consistent_np: NO
Checking for declaration of PTHREAD_MUTEX_ROBUST: NO
Checking for declaration of PTHREAD_MUTEX_ROBUST (as enum): NO
Checking for declaration of PTHREAD_MUTEX_ROBUST_NP: NO
Checking for declaration of PTHREAD_MUTEX_ROBUST_NP (as enum): NO
Checking for get_current_dir_name: NO
Checking for getgrent_r: NO
Checking for getpwent_r: NO
Checking for declaration of getgrent_r: NO
Checking for declaration of getgrent_r (as enum): NO
Checking for declaration of getpwent_r: NO
Checking for declaration of getpwent_r (as enum): NO
Checking for siggetmask: NO
Checking for memset_s: NO
Checking for shl_load: NO
Checking for shl_unload: NO
Checking for shl_findsym: NO
Checking for chsize: NO
Checking for __strtoull: NO
Checking for strtouq: NO
Checking for __strtoll: NO
Checking for strtoq: NO
Checking for variable rl_event_hook: NO
Checking for variable program_invocation_short_name: NO
Checking for atomic_add_32 compiler builtin: NO
Checking for declaration of dgettext: NO
Checking for declaration of dgettext (as enum): NO
Checking for declaration of gettext: NO
Checking for declaration of gettext (as enum): NO
Checking for declaration of bindtextdomain: NO
Checking for declaration of bindtextdomain (as enum): NO
Checking for declaration of textdomain: NO
Checking for declaration of textdomain (as enum): NO
Checking for declaration of bind_textdomain_codeset: NO
Checking for declaration of bind_textdomain_codeset (as enum): NO
Checking for bindtextdomain: NO
Checking for textdomain: NO
Checking for bind_textdomain_codeset: NO
Checking for dgettext: NO
Checking for gettext: NO
Checking for offset_t: NO
Checking for member __ss_family in struct sockaddr_storage: NO
Checking for member sa_len in struct sockaddr: NO
Checking for member sin_len in struct sockaddr_in: NO
Checking for member sin6_len in struct sockaddr_in6: NO
ENDANSWERS
    
    CC="$CC" AR="$AR" RANLIB="$RANLIB" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    ./configure \
        --cross-compile \
        --cross-answers=$PWD/cross-answers.txt \
        --prefix=$WORK_DIR/talloc_install \
        --disable-python \
        --disable-rpath-install
fi

make -j$(nproc)
make install

TALLOC_DIR=$WORK_DIR/talloc_install
echo "=== talloc собран! ==="
ls -la $TALLOC_DIR/lib/

cd $WORK_DIR

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
