#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/tryweb/text-to-cad-dockerkit/main"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ──────────────────────────────────────────────────────────
# Color helpers (disabled if not terminal)
# ──────────────────────────────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

info()  { echo -e "  ${CYAN}ℹ${NC}  $1"; }
ok()    { echo -e "  ${GREEN}✅${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠️${NC}  $1"; }
fail()  { echo -e "  ${RED}❌${NC} $1"; exit 1; }
header() {
    echo
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD} $1${NC}"
    echo -e "${BOLD}========================================${NC}"
}

# ──────────────────────────────────────────────────────────
# Step 1 — System requirements
# ──────────────────────────────────────────────────────────
check_system() {
    header "1. 檢查系統硬體規格"

    CPU_CORES=$(nproc 2>/dev/null || echo 0)
    RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    RAM_GB=$((RAM_KB / 1024 / 1024))
    DISK_KB=$(df -Pk / 2>/dev/null | tail -1 | awk '{print $4}')
    DISK_GB=$((DISK_KB / 1024 / 1024))

    echo "  CPU cores: $CPU_CORES  |  RAM: ${RAM_GB} GB (${RAM_KB} KB)  |  Disk: ${DISK_GB} GB"

    if [ "$CPU_CORES" -lt 2 ]; then
        fail "CPU 核心數不足 (需要至少 2 core)"
    fi
    if [ "$RAM_KB" -lt $((3 * 1024 * 1024)) ]; then
        fail "RAM 不足 (需要至少 3 GB, 目前 ${RAM_KB} KB)"
    fi
    if [ "$DISK_GB" -lt 5 ]; then
        fail "磁碟空間不足 (至少需要 5 GB 以進行升級)"
    fi

    ok "系統規格符合要求"
}

# ──────────────────────────────────────────────────────────
# Step 2 — Docker environment
# ──────────────────────────────────────────────────────────
check_docker() {
    header "2. 檢查 Docker 環境"

    command -v docker &>/dev/null || fail "Docker 未安裝"
    ok "Docker: $(docker --version | head -1)"

    if command -v docker compose &>/dev/null; then
        ok "Docker Compose V2 已安裝"
    elif docker compose version &>/dev/null 2>&1; then
        ok "Docker Compose V2 已安裝 (plugin)"
    else
        fail "Docker Compose V2 未安裝"
    fi

    [ -S /var/run/docker.sock ] || fail "Docker socket 不存在"
    docker info &>/dev/null || fail "無法連接 Docker daemon"
    ok "Docker daemon 運作正常"

    command -v curl &>/dev/null || command -v wget &>/dev/null || fail "缺少 curl 或 wget"
    ok "網路工具已安裝"
}

# ──────────────────────────────────────────────────────────
# Step 3 — Backup existing files
# ──────────────────────────────────────────────────────────
backup_files() {
    header "3. 備份既有設定檔"

    local backup_dir="backup_${TIMESTAMP}"
    mkdir -p "$backup_dir"

    for f in docker-compose.yml docker-compose.dev.yml .env entrypoint.sh; do
        if [ -f "$f" ]; then
            cp "$f" "${backup_dir}/${f}"
            ok "${f} → ${backup_dir}/${f}"
        else
            info "${f} 不存在，跳過備份"
        fi
    done

    if [ -d "scripts" ]; then
        cp -r scripts "${backup_dir}/scripts"
        ok "scripts/ → ${backup_dir}/scripts/"
    fi
}

download_file() {
    local url="$1" output="$2"
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$output"
    else
        wget -q "$url" -O "$output"
    fi
}

fetch_stdout() {
    if command -v curl &>/dev/null; then
        curl -fsSL "$1"
    else
        wget -q "$1" -O-
    fi
}

# ──────────────────────────────────────────────────────────
# Step 4 — Update compose files from upstream
# ──────────────────────────────────────────────────────────
update_compose() {
    header "4. 更新 docker-compose 檔案"

    for f in docker-compose.yml docker-compose.dev.yml; do
        echo "  下載最新 ${f}..."
        if download_file "$REPO_URL/${f}" "${f}.new" && [ -s "${f}.new" ]; then
            mv "${f}.new" "${f}"
            ok "${f} 已更新"
        else
            rm -f "${f}.new"
            warn "${f} 下載失敗，使用既有版本"
        fi
    done
}

# ──────────────────────────────────────────────────────────
# Step 5 — Merge new env vars into .env
# ──────────────────────────────────────────────────────────
merge_env() {
    header "5. 合併 .env 設定"

    if [ ! -f ".env" ]; then
        warn ".env 不存在，從 upstream 下載"
        download_file "$REPO_URL/.env.example" .env
        ok ".env 已建立 (使用預設值)"
        info "請編輯 .env 中的 LOCAL_UID / LOCAL_GID 等自訂值"
        return
    fi

    local tmp_example
    tmp_example=$(mktemp)
    fetch_stdout "$REPO_URL/.env.example" > "$tmp_example" || {
        rm -f "$tmp_example"
        warn "無法下載 .env.example，跳過 env 合併"
        return
    }

    local added=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// /}" ]] && continue

        key="${line%%=*}"
        key="${key## }"; key="${key%% }"

        if grep -qE "^(export[[:space:]]+)?${key}=" .env 2>/dev/null; then
            :
        else
            echo "$line" >> .env
            added=$((added + 1))
            echo -e "  ${GREEN}➕${NC} ${key} 已新增至 .env"
        fi
    done < "$tmp_example"

    rm -f "$tmp_example"

    if [ "$added" -gt 0 ]; then
        ok "已合併 ${added} 個新設定值到 .env"
    else
        ok ".env 已包含所有最新設定，無需變更"
    fi
}

# ──────────────────────────────────────────────────────────
# Step 6 — Pull latest image
# ──────────────────────────────────────────────────────────
pull_image() {
    header "6. 拉取最新 Docker 映像"

    local old_id
    old_id=$(docker images --filter "reference=ghcr.io/tryweb/text-to-cad-dockerkit" -q 2>/dev/null | head -1 || true)
    if [ -n "$old_id" ]; then
        echo "  當前映像 ID: ${old_id:0:12}"
    else
        info "本地尚無 ghcr.io/tryweb/text-to-cad-dockerkit 映像"
    fi

    echo "  正在拉取..."
    if docker compose pull 2>&1; then
        ok "映像已更新至最新版"
    else
        warn "拉取失敗，將使用本地快取"
    fi

    local new_id
    new_id=$(docker images --filter "reference=ghcr.io/tryweb/text-to-cad-dockerkit" -q 2>/dev/null | head -1 || true)
    if [ -n "$new_id" ] && [ "$new_id" != "$old_id" ] && [ -n "$old_id" ]; then
        echo "  新映像 ID: ${new_id:0:12}"
    fi
}

# ──────────────────────────────────────────────────────────
# Step 7 — Recreate containers
# ──────────────────────────────────────────────────────────
recreate_containers() {
    header "7. 重建容器"

    if [ -f ".env" ]; then
        local ws_vol
        ws_vol=$(grep -E "^WORKSPACE_VOLUME_NAME=" .env 2>/dev/null | head -1 | cut -d= -f2-)
        if [ -n "$ws_vol" ] && [ ! -d "$ws_vol" ] && [[ "$ws_vol" != cad-* ]]; then
            # If it looks like a bind-mount path, ensure it exists
            if [[ "$ws_vol" =~ / ]]; then
                warn "WORKSPACE_VOLUME_NAME=${ws_vol} 目錄不存在，將自動建立"
                mkdir -p "$ws_vol"
            fi
        fi
    fi

    echo "  執行 docker compose up -d --force-recreate..."
    docker compose up -d --force-recreate 2>&1 || fail "容器啟動失敗，請檢查 docker compose ps"

    echo -n "  等待服務啟動"
    for _ in $(seq 1 30); do
        STATUS=$(docker inspect cad-workbench --format='{{.State.Status}}' 2>/dev/null)
        if [ "$STATUS" = "running" ]; then
            echo
            ok "容器已重新啟動"
            break
        fi
        echo -n "."
        sleep 2
    done

    echo -n "  等待初始化"
    sleep 10
    echo

    docker compose ps
}

# ──────────────────────────────────────────────────────────
# Step 8 — Verify
# ──────────────────────────────────────────────────────────
run_verification() {
    header "8. 驗證服務"

    if [ -f "./scripts/verify.sh" ]; then
        if [ -f "docker-compose.dev.yml" ]; then
            export COMPOSE_FILE="docker-compose.yml:docker-compose.dev.yml"
        fi
        if ./scripts/verify.sh; then
            ok "所有驗證通過"
        else
            warn "部分驗證失敗，請檢查 docker compose logs"
        fi
    else
        warn "scripts/verify.sh 不存在，跳過驗證"
    fi
}

# ──────────────────────────────────────────────────────────
# Step 9 — Clean up dangling images
# ──────────────────────────────────────────────────────────
cleanup_images() {
    header "9. 清理舊映像"

    local pruned
    pruned=$(docker image prune -f 2>&1 | grep -oP 'Total reclaimed space: \K.*' || true)
    if [ -n "$pruned" ]; then
        ok "已釋放磁碟空間: ${pruned}"
    else
        info "無需清理"
    fi
}

# ──────────────────────────────────────────────────────────
# Step 10 — Show upgrade summary
# ──────────────────────────────────────────────────────────
show_info() {
    local host_ip=""
    if command -v ip &>/dev/null; then
        host_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[^ ]+' | head -1)
    elif command -v hostname &>/dev/null; then
        host_ip=$(hostname -I 2>/dev/null | awk '{print $1}' | grep -v '^fe80\|^::' | head -1)
    fi

    if [ -f ".env" ]; then
        # shellcheck source=/dev/null
        source .env
    fi
    TTYD_PORT="${OPENCODE_TTYD_PORT:-3001}"
    VIEWER_PORT="${VIEWER_HOST_PORT:-3002}"

    echo
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  Upgrade Complete!${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo
    echo -e "  ${CYAN}🌐${NC} Terminal: http://${host_ip:-localhost}:${TTYD_PORT}"
    echo -e "  ${CYAN}🌐${NC} Viewer:   http://${host_ip:-localhost}:${VIEWER_PORT}"
    echo
    if [ -n "$host_ip" ] && [[ ! "$host_ip" =~ ^127\. ]]; then
        echo "  外部存取請使用上述 IP (非 localhost)"
    fi
    echo
    echo -e "  ${YELLOW}ℹ${NC}  備份目錄: backup_${TIMESTAMP}/"
    echo "     (包含升級前的 compose 檔案與 .env)"
    echo
    echo -e "  ${YELLOW}ℹ${NC}  若需回滾:"
    echo "     docker compose down"
    echo "     cp backup_${TIMESTAMP}/docker-compose.yml docker-compose.yml"
    echo "     cp backup_${TIMESTAMP}/.env .env"
    echo "     docker compose up -d"
    echo
    echo -e "${BOLD}========================================${NC}"
}

# ──────────────────────────────────────────────────────────
# Verify we're in an installed environment
# ──────────────────────────────────────────────────────────
verify_installed() {
    if [ ! -f "docker-compose.yml" ]; then
        fail "找不到安裝環境 (缺少 docker-compose.yml)。

upgrade.sh 僅供已安裝環境使用。首次安裝請執行:

  curl -fsSL https://raw.githubusercontent.com/tryweb/text-to-cad-dockerkit/main/install.sh | bash"
    fi
}

# ──────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────
main() {
    cd "$(dirname "$0")"

    verify_installed

    echo
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   text-to-cad Workbench 升級腳本     ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"

    check_system
    check_docker
    backup_files
    update_compose
    merge_env
    pull_image
    recreate_containers
    run_verification
    cleanup_images
    show_info
}

main "$@"
