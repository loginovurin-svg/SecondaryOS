#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecondaryOS
# scripts/prepare_assets.sh
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT/app/src/main/assets"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== SecondaryOS prepare_assets ==="
echo "ROOT:       $ROOT"
echo "ASSETS_DIR: $ASSETS_DIR"
echo "TMP_DIR:    $TMP_DIR"
echo

REQUIRED_COMMANDS=(curl file tar grep)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ОШИБКА: не найдена обязательная команда: $cmd"
        exit 1
    fi
done

mkdir -p "$ASSETS_DIR"

echo "=== Очистка старых артефактов ==="
rm -rf \
    "$ASSETS_DIR/proot_static" \
    "$ASSETS_DIR/debian-rootfs.tar.xz" \
    "$ASSETS_DIR/debian-rootfs.tar.gz" \
    "$ASSETS_DIR/debian-rootfs.tgz" \
    "$ASSETS_DIR/debian-rootfs.tar"

echo "Очистка завершена."
echo

# Жестко задаем URL статического бинарника proot
PROOT_URL="${PROOT_URL:-https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-aarch64-static}"
ROOTFS_URL="${ROOTFS_URL:-}"

download_file() {
    local url="$1"
    local out="$2"
    echo "Скачиваю:"
    echo "  URL: $url"
    curl -fL --retry 3 --retry-delay 2 -o "$out" "$url"
    echo "Файл скачан: $(du -h "$out" | cut -f1)"
    echo
}

echo "=== Получение proot ==="
PROOT_ASSET="$TMP_DIR/proot_asset"
PROOT_FINAL="$ASSETS_DIR/proot_static"

download_file "$PROOT_URL" "$PROOT_ASSET"

# Проверка, что это ELF бинарник
if ! file "$PROOT_ASSET" | grep -qi 'ELF'; then
    echo "ПРЕДУПРЕЖДЕНИЕ: скачанный proot не похож на ELF бинарник."
    file "$PROOT_ASSET"
fi

cp "$PROOT_ASSET" "$PROOT_FINAL"
chmod 0755 "$PROOT_FINAL"
echo "Проверка file для proot:"
file "$PROOT_FINAL" || true
echo "proot_static помещён сюда: $PROOT_FINAL"
echo

echo "=== Получение Debian rootfs ==="
ROOTFS_ASSET="$TMP_DIR/rootfs_asset"

if [[ -z "$ROOTFS_URL" ]]; then
    echo "ROOTFS_URL не задан. Ищу последний rootfs на images.linuxcontainers.org..."
    ROOTFS_BASE_URL="https://images.linuxcontainers.org/images/debian/bookworm/arm64/default"
    
    # Получаем список папок с датами, берем последнюю.
    # Сервер кодирует двоеточие как %3A в HTML, поэтому ищем %3A.
    LATEST_DIR=$(curl -fsSL "$ROOTFS_BASE_URL/" | grep -oP '(?<=href=")[0-9]{8}_[0-9]{2}%3A[0-9]{2}' | sort | tail -n 1)
    
    if [[ -z "$LATEST_DIR" ]]; then
        echo "ОШИБКА: не удалось найти последнюю папку с rootfs на images.linuxcontainers.org"
        exit 1
    fi
    
    ROOTFS_URL="$ROOTFS_BASE_URL/$LATEST_DIR/rootfs.tar.xz"
    echo "Найдена последняя сборка: $LATEST_DIR"
fi

download_file "$ROOTFS_URL" "$ROOTFS_ASSET"

echo "=== Подготовка rootfs archive ==="
file "$ROOTFS_ASSET" || true

if file "$ROOTFS_ASSET" | grep -qi 'XZ compressed'; then
    cp "$ROOTFS_ASSET" "$ASSETS_DIR/debian-rootfs.tar.xz"
elif file "$ROOTFS_ASSET" | grep -qi 'gzip compressed'; then
    cp "$ROOTFS_ASSET" "$ASSETS_DIR/debian-rootfs.tar.gz"
elif tar -tf "$ROOTFS_ASSET" >/dev/null 2>&1; then
    if command -v xz >/dev/null 2>&1; then
        xz -zc "$ROOTFS_ASSET" > "$ASSETS_DIR/debian-rootfs.tar.xz"
    elif command -v gzip >/dev/null 2>&1; then
        gzip -c "$ROOTFS_ASSET" > "$ASSETS_DIR/debian-rootfs.tar.gz"
    else
        cp "$ROOTFS_ASSET" "$ASSETS_DIR/debian-rootfs.tar"
    fi
else
    echo "ОШИБКА: не понимаю формат rootfs."
    exit 1
fi

echo
echo "Готовые assets:"
ls -lh "$ASSETS_DIR"
echo "=== prepare_assets.sh завершён успешно ==="
