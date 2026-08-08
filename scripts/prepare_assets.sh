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

REQUIRED_COMMANDS=(curl jq file tar dpkg-deb zgrep)

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

PROOT_URL="${PROOT_URL:-}"
ROOTFS_URL="${ROOTFS_URL:-}"

ROOTFS_RELEASE_REPO="${ROOTFS_RELEASE_REPO:-termux/proot-distro}"
# Исправленный паттерн: ищем debian, aarch64 и tar.xz/tar.gz без обязательного слова rootfs
ROOTFS_ASSET_PATTERN="${ROOTFS_ASSET_PATTERN:-debian.*aarch64.*\\.tar\\.(xz|gz)}"

github_curl() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$@"
    else
        curl -fsSL "$@"
    fi
}

download_file() {
    local url="$1"
    local out="$2"
    echo "Скачиваю:"
    echo "  URL: $url"
    curl -fL --retry 3 --retry-delay 2 -o "$out" "$url"
    echo "Файл скачан: $(du -h "$out" | cut -f1)"
    echo
}

github_latest_asset_url() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local response
    if ! response="$(github_curl -H "Accept: application/vnd.github+json" "$api_url" 2>/dev/null)"; then
        return 0
    fi
    if [[ -z "$response" ]]; then
        return 0
    fi
    printf '%s\n' "$response" |
        jq -r --arg pat "$pattern" '
            (.assets // [])[]
            | .browser_download_url
            | select(test($pat; "i"))
        ' 2>/dev/null |
        head -n 1 || true
}

# Новая функция: скачиваем .deb пакет proot из официального репозитория Termux
download_proot_from_termux_repo() {
    local tmp_dir="$1"
    local out_file="$2"
    
    local repo_base="https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64"
    local packages_gz="$tmp_dir/Packages.gz"
    
    echo "Скачиваю список пакетов Termux..."
    if ! curl -fsSL "$repo_base/Packages.gz" -o "$packages_gz"; then
        echo "ОШИБКА: не удалось скачать Packages.gz"
        return 1
    fi
    
    echo "Ищу пакет proot..."
    local deb_path
    deb_path=$(zgrep -A 20 "^Package: proot$" "$packages_gz" | grep "^Filename:" | awk '{print $2}' | head -n 1)
    
    if [[ -z "$deb_path" ]]; then
        echo "ОШИБКА: пакет proot не найден в репозитории Termux"
        return 1
    fi
    
    local deb_url="https://packages.termux.dev/apt/termux-main/$deb_path"
    local deb_file="$tmp_dir/proot.deb"
    
    echo "Скачиваю .deb пакет: $deb_url"
    curl -fL --retry 3 -o "$deb_file" "$deb_url"
    
    echo "Распаковываю .deb пакет через dpkg-deb..."
    local fs_dir="$tmp_dir/proot_fs"
    mkdir -p "$fs_dir"
    
    dpkg-deb -x "$deb_file" "$fs_dir"
    
    local proot_bin
    proot_bin=$(find "$fs_dir" -type f -name "proot" -print -quit)
    
    if [[ -z "$proot_bin" ]]; then
        echo "ОШИБКА: бинарник proot не найден внутри .deb пакета"
        find "$fs_dir"
        return 1
    fi
    
    echo "Найден бинарник: $proot_bin"
    cp "$proot_bin" "$out_file"
    return 0
}

echo "=== Получение proot ==="
PROOT_ASSET="$TMP_DIR/proot_asset"
PROOT_FINAL="$ASSETS_DIR/proot_static"

if [[ -n "$PROOT_URL" ]]; then
    download_file "$PROOT_URL" "$PROOT_ASSET"
    cp "$PROOT_ASSET" "$PROOT_FINAL"
else
    echo "PROOT_URL не задан. Скачиваю из репозитория пакетов Termux."
    if ! download_proot_from_termux_repo "$TMP_DIR" "$PROOT_FINAL"; then
        echo "ОШИБКА: не удалось получить proot."
        exit 1
    fi
fi

chmod 0755 "$PROOT_FINAL"
echo "Проверка file для proot:"
file "$PROOT_FINAL" || true
echo "proot_static помещён сюда: $PROOT_FINAL"
echo

echo "=== Получение Debian rootfs ==="
ROOTFS_ASSET="$TMP_DIR/rootfs_asset"

if [[ -n "$ROOTFS_URL" ]]; then
    download_file "$ROOTFS_URL" "$ROOTFS_ASSET"
else
    echo "ROOTFS_URL не задан. Ищу asset в GitHub release."
    echo "Репозиторий: $ROOTFS_RELEASE_REPO"
    echo "Паттерн:      $ROOTFS_ASSET_PATTERN"

    ROOTFS_ASSET_URL="$(github_latest_asset_url "$ROOTFS_RELEASE_REPO" "$ROOTFS_ASSET_PATTERN" || true)"

    if [[ -z "$ROOTFS_ASSET_URL" ]]; then
        echo "ОШИБКА: не удалось автоматически найти Debian rootfs."
        exit 1
    fi

    download_file "$ROOTFS_ASSET_URL" "$ROOTFS_ASSET"
fi

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
