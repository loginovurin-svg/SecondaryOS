#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SecondaryOS
# scripts/prepare_assets.sh
#
# Задача:
# - удалить старые попытки компиляции proot/talloc
# - скачать готовый proot для aarch64
# - скачать готовый Debian rootfs
# - положить их в app/src/main/assets
#
# Никакой компиляции gcc/clang/waf/qemu здесь не делаем.
# Только curl, jq, file, tar, xz/gzip/unzip при необходимости.
# ============================================================

# Корень проекта
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT/app/src/main/assets"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT

echo "=== SecondaryOS prepare_assets ==="
echo "ROOT:       $ROOT"
echo "ASSETS_DIR: $ASSETS_DIR"
echo "TMP_DIR:    $TMP_DIR"
echo

# ------------------------------------------------------------
# Проверяем обязательные инструменты
# ------------------------------------------------------------
REQUIRED_COMMANDS=(curl jq file tar)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ОШИБКА: не найдена обязательная команда: $cmd"
        echo "Установи её и запусти скрипт снова."
        exit 1
    fi
done

mkdir -p "$ASSETS_DIR"

# ------------------------------------------------------------
# 1. Удаляем старые попытки компиляции и старые артефакты
# ------------------------------------------------------------
echo "=== Очистка старых артефактов ==="

rm -rf \
    "$ROOT/third_party" \
    "$ROOT/proot" \
    "$ROOT/talloc" \
    "$ROOT/proot-src" \
    "$ROOT/talloc-src" \
    "$ROOT/proot-build" \
    "$ROOT/app/src/main/cpp/proot" \
    "$ROOT/app/src/main/cpp/talloc" \
    "$ASSETS_DIR/proot_static" \
    "$ASSETS_DIR/debian-rootfs.tar.xz" \
    "$ASSETS_DIR/debian-rootfs.tar.gz" \
    "$ASSETS_DIR/debian-rootfs.tgz" \
    "$ASSETS_DIR/debian-rootfs.tar"

echo "Очистка завершена."
echo

# ------------------------------------------------------------
# 2. Настройки источников
# ------------------------------------------------------------
# Если есть прямые ссылки, можно задать их через окружение:
#
# PROOT_URL="https://example.com/proot-aarch64-static" \
# ROOTFS_URL="https://example.com/debian-aarch64-rootfs.tar.xz" \
# bash scripts/prepare_assets.sh
#
# Если прямых ссылок нет, скрипт попробует найти asset
# в последнем GitHub release по регулярному выражению.

PROOT_URL="${PROOT_URL:-}"
ROOTFS_URL="${ROOTFS_URL:-}"

# Репозитории, где ищем proot.
# Порядок важен.
PROOT_RELEASE_REPOS=(
    "${PROOT_RELEASE_REPO:-termux/proot}"
    "termux/proot-distro"
    "proot-me/proot"
)

# Репозиторий, где ищем rootfs.
ROOTFS_RELEASE_REPO="${ROOTFS_RELEASE_REPO:-termux/proot-distro}"

# Маски поиска файлов.
# Можно переопределить через окружение, если имена изменятся.
PROOT_ASSET_PATTERN="${PROOT_ASSET_PATTERN:-proot.*aarch64}"
ROOTFS_ASSET_PATTERN="${ROOTFS_ASSET_PATTERN:-debian.*aarch64.*rootfs.*\\.tar\\.(xz|gz)}"

# ------------------------------------------------------------
# 3. Вспомогательные функции
# ------------------------------------------------------------

github_curl() {
    # Если задан GITHUB_TOKEN, используем его.
    # Это помогает обходить лимиты GitHub API.
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
    echo "  OUT: $out"

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

    # Ищем первый подходящий asset по регулярному выражению.
    printf '%s\n' "$response" |
        jq -r --arg pat "$pattern" '
            (.assets // [])[]
            | .browser_download_url
            | select(test($pat; "i"))
        ' 2>/dev/null |
        head -n 1 || true
}

find_binary_after_extract() {
    local dir="$1"

    # Ищем бинарник proot внутри распакованной папки
    find "$dir" -type f -name 'proot*' -print -quit
}

extract_proot_asset() {
    local asset="$1"
    local final="$2"
    local extract_dir="$3"

    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"

    echo "Определяю тип файла proot..."
    file "$asset" || true

    # Если уже ELF-бинарник, просто копируем.
    if file "$asset" | grep -qi 'ELF'; then
        echo "Похоже, уже готовый ELF-бинарник."
        cp "$asset" "$final"
        return 0
    fi

    # .deb из Termux обычно не подходит как один статический бинарник.
    if file "$asset" | grep -qi 'debian binary package'; then
        echo "ОШИБКА: получен .deb пакет."
        echo "Нужен один статический aarch64 бинарник proot, а не .deb."
        exit 1
    fi

    # tar.xz
    if file "$asset" | grep -qi 'XZ compressed'; then
        echo "Похоже, tar.xz архив. Распаковываю."
        tar -xJf "$asset" -C "$extract_dir"

        local bin
        bin="$(find_binary_after_extract "$extract_dir")"

        if [[ -z "$bin" ]]; then
            echo "ОШИБКА: внутри архива не найден бинарник proot" >&2
            exit 1
        fi

        cp "$bin" "$final"
        return 0
    fi

    # tar.gz
    if file "$asset" | grep -qi 'gzip compressed'; then
        echo "Похоже, tar.gz архив. Распаковываю."
        tar -xzf "$asset" -C "$extract_dir"

        local bin
        bin="$(find_binary_after_extract "$extract_dir")"

        if [[ -z "$bin" ]]; then
            echo "ОШИБКА: внутри архива не найден бинарник proot" >&2
            exit 1
        fi

        cp "$bin" "$final"
        return 0
    fi

    # Обычный tar
    if tar -tf "$asset" >/dev/null 2>&1; then
        echo "Похоже, обычный tar архив. Распаковываю."
        tar -xf "$asset" -C "$extract_dir"

        local bin
        bin="$(find_binary_after_extract "$extract_dir")"

        if [[ -z "$bin" ]]; then
            echo "ОШИБКА: внутри архива не найден бинарник proot" >&2
            exit 1
        fi

        cp "$bin" "$final"
        return 0
    fi

    # zip
    if file "$asset" | grep -qi 'Zip archive'; then
        if ! command -v unzip >/dev/null 2>&1; then
            echo "ОШИБКА: найден zip архив, но не установлен unzip."
            exit 1
        fi

        echo "Похоже, zip архив. Распаковываю."
        unzip -q "$asset" -d "$extract_dir"

        local bin
        bin="$(find_binary_after_extract "$extract_dir")"

        if [[ -z "$bin" ]]; then
            echo "ОШИБКА: внутри архива не найден бинарник proot" >&2
            exit 1
        fi

        cp "$bin" "$final"
        return 0
    fi

    # Если не поняли формат, считаем сырым бинарником.
    echo "Неизвестный формат. Считаю файл сырым бинарником."
    cp "$asset" "$final"
}

# ------------------------------------------------------------
# 4. Скачиваем proot
# ------------------------------------------------------------
echo "=== Получение proot ==="

PROOT_ASSET="$TMP_DIR/proot_asset"

if [[ -n "$PROOT_URL" ]]; then
    download_file "$PROOT_URL" "$PROOT_ASSET"
else
    echo "PROOT_URL не задан. Ищу asset в GitHub releases."

    PROOT_ASSET_URL=""

    for repo in "${PROOT_RELEASE_REPOS[@]}"; do
        echo "Пробую репозиторий: $repo"
        echo "Паттерн: $PROOT_ASSET_PATTERN"

        PROOT_ASSET_URL="$(github_latest_asset_url "$repo" "$PROOT_ASSET_PATTERN" || true)"

        if [[ -n "$PROOT_ASSET_URL" ]]; then
            echo "Найден asset в $repo"
            break
        fi
    done

    if [[ -z "$PROOT_ASSET_URL" ]]; then
        echo
        echo "ОШИБКА: не удалось автоматически найти готовый proot."
        echo "Запусти скрипт вручную, например:"
        echo
        echo "PROOT_URL=\"https://.../proot-aarch64-static\" bash scripts/prepare_assets.sh"
        echo
        exit 1
    fi

    download_file "$PROOT_ASSET_URL" "$PROOT_ASSET"
fi

# ------------------------------------------------------------
# 5. Распаковка/нормализация proot
# ------------------------------------------------------------
echo "=== Подготовка proot_static ==="

PROOT_FINAL="$ASSETS_DIR/proot_static"
PROOT_EXTRACT_DIR="$TMP_DIR/proot_extract"

extract_proot_asset "$PROOT_ASSET" "$PROOT_FINAL" "$PROOT_EXTRACT_DIR"

chmod 0755 "$PROOT_FINAL"

echo "Проверка file:"
file "$PROOT_FINAL" || true

if ! file "$PROOT_FINAL" | grep -qi 'aarch64'; then
    echo "ПРЕДУПРЕЖДЕНИЕ: proot_static не похож на aarch64 бинарник."
fi

if ! file "$PROOT_FINAL" | grep -qi 'statically linked'; then
    echo "ПРЕДУПРЕЖДЕНИЕ: proot_static не похож на статически связанный бинарник."
    echo "Если он динамический, он может не запуститься без зависимостей."
fi

echo
echo "proot_static помещён сюда: $PROOT_FINAL"
echo

# ------------------------------------------------------------
# 6. Скачиваем Debian rootfs
# ------------------------------------------------------------
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
        echo
        echo "ОШИБКА: не удалось автоматически найти Debian rootfs."
        echo "Запусти скрипт вручную, например:"
        echo
        echo "ROOTFS_URL=\"https://.../debian-aarch64-rootfs.tar.xz\" bash scripts/prepare_assets.sh"
        echo
        exit 1
    fi

    download_file "$ROOTFS_ASSET_URL" "$ROOTFS_ASSET"
fi

# ------------------------------------------------------------
# 7. Кладём rootfs в assets с понятным именем
# ------------------------------------------------------------
echo "=== Подготовка rootfs archive ==="

echo "Определяю тип rootfs..."
file "$ROOTFS_ASSET" || true

if file "$ROOTFS_ASSET" | grep -qi 'XZ compressed'; then
    echo "Rootfs уже tar.xz."
    cp "$ROOTFS_ASSET" "$ASSETS_DIR/debian-rootfs.tar.xz"

elif file "$ROOTFS_ASSET" | grep -qi 'gzip compressed'; then
    echo "Rootfs уже tar.gz."
    cp "$ROOTFS_ASSET" "$ASSETS_DIR/debian-rootfs.tar.gz"

elif tar -tf "$ROOTFS_ASSET" >/dev/null 2>&1; then
    echo "Rootfs похоже обычный tar."

    if command -v xz >/dev/null 2>&1; then
        echo "Сжимаю в xz."
        xz -zc "$ROOTFS_ASSET" > "$ASSETS_DIR/debian-rootfs.tar.xz"
    elif command -v gzip >/dev/null 2>&1; then
        echo "xz нет, сжимаю в gzip."
        gzip -c "$ROOTFS_ASSET" > "$ASSETS_DIR/debian-rootfs.tar.gz"
    else
        echo "Ни xz, ни gzip не найдены. Кладу как debian-rootfs.tar"
        cp "$ROOTFS_ASSET" "$ASSETS_DIR/debian-rootfs.tar"
    fi

else
    echo "ОШИБКА: не понимаю формат rootfs." >&2
    file "$ROOTFS_ASSET" || true
    exit 1
fi

echo
echo "Готовые assets:"
ls -lh "$ASSETS_DIR"

echo
echo "=== prepare_assets.sh завершён успешно ==="
