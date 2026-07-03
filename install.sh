#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/tryweb/text-to-cad-dockerkit/main"

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
# Env helpers
# ──────────────────────────────────────────────────────────
set_env_value() {
    local key="$1" value="$2"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}=" .env 2>/dev/null; then
        sed -i "s|^[[:space:]]*#\{0,1\}[[:space:]]*${key}=.*|${key}=${value}|" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

# ──────────────────────────────────────────────────────────
# Download helper (curl/wget abstraction)
# ──────────────────────────────────────────────────────────
download_file() {
    local url="$1" output="$2"
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$output"
    else
        wget -q "$url" -O "$output"
    fi
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
    if [ "$DISK_KB" -lt $((10 * 1024 * 1024)) ]; then
        fail "磁碟空間不足 (需要至少 10 GB)"
    fi

    ok "系統規格符合要求"
}

# ──────────────────────────────────────────────────────────
# Step 2 — Docker environment
# ──────────────────────────────────────────────────────────
check_docker() {
    header "2. 檢查 Docker 環境"

    if ! command -v docker &>/dev/null; then
        fail "Docker 未安裝，請參考: https://docs.docker.com/get-docker/"
    fi
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
# Step 3 — Download configuration files
# ──────────────────────────────────────────────────────────
download_files() {
    header "3. 下載設定檔案"

    if [ ! -f "docker-compose.yml" ]; then
        echo "  下載 docker-compose.yml..."
        download_file "$REPO_URL/docker-compose.yml" docker-compose.yml
        ok "docker-compose.yml 已下載"
    else
        ok "docker-compose.yml 已存在"
    fi

    if [ ! -f "docker-compose.dev.yml" ]; then
        echo "  下載 docker-compose.dev.yml..."
        download_file "$REPO_URL/docker-compose.dev.yml" docker-compose.dev.yml
        ok "docker-compose.dev.yml 已下載"
    else
        ok "docker-compose.dev.yml 已存在"
    fi

    if [ ! -f ".env" ]; then
        echo "  下載 .env.example..."
        download_file "$REPO_URL/.env.example" .env
        ok ".env 已建立，請編輯設定"
    else
        ok ".env 已存在"
    fi

    if [ ! -f "entrypoint.sh" ]; then
        echo "  下載 entrypoint.sh..."
        download_file "$REPO_URL/entrypoint.sh" entrypoint.sh
        chmod +x entrypoint.sh
        ok "entrypoint.sh 已下載"
    else
        ok "entrypoint.sh 已存在"
    fi

    if [ ! -d "scripts" ]; then
        mkdir -p scripts
    fi

    if [ ! -f "scripts/verify.sh" ]; then
        echo "  下載 scripts/verify.sh..."
        download_file "$REPO_URL/scripts/verify.sh" scripts/verify.sh
        chmod +x scripts/verify.sh
        ok "scripts/verify.sh 已下載"
    else
        ok "scripts/verify.sh 已存在"
    fi

    echo
    echo "  下載最新 upgrade.sh..."
    download_file "$REPO_URL/upgrade.sh" upgrade.sh
    chmod +x upgrade.sh
    ok "upgrade.sh 已就緒 (後續執行 ./upgrade.sh 即可升級)"
}

# ──────────────────────────────────────────────────────────
# Step 4 — Environment setup
# ──────────────────────────────────────────────────────────
setup_env() {
    header "4. 環境設定"

    if [ -f ".env" ]; then
        # shellcheck source=/dev/null
        source .env
    fi

    # LOCAL_UID
    CURRENT_UID=$(id -u 2>/dev/null || echo "1000")
    if [ -z "${LOCAL_UID:-}" ]; then
        read -r -p "  輸入 LOCAL_UID (Enter 使用預設 ${CURRENT_UID}): " UID_INPUT
        LOCAL_UID="${UID_INPUT:-$CURRENT_UID}"
        set_env_value "LOCAL_UID" "$LOCAL_UID"
        ok "LOCAL_UID 已設定為 ${LOCAL_UID}"
    else
        ok "LOCAL_UID 已設定 (${LOCAL_UID})"
    fi

    # LOCAL_GID
    CURRENT_GID=$(id -g 2>/dev/null || echo "1000")
    if [ -z "${LOCAL_GID:-}" ]; then
        read -r -p "  輸入 LOCAL_GID (Enter 使用預設 ${CURRENT_GID}): " GID_INPUT
        LOCAL_GID="${GID_INPUT:-$CURRENT_GID}"
        set_env_value "LOCAL_GID" "$LOCAL_GID"
        ok "LOCAL_GID 已設定為 ${LOCAL_GID}"
    else
        ok "LOCAL_GID 已設定 (${LOCAL_GID})"
    fi

    # Ports
    if [ -z "${OPENCODE_TTYD_PORT:-}" ]; then
        read -r -p "  輸入 Terminal 埠號 (Enter 使用預設 3001): " TTYD_INPUT
        TTYD_PORT="${TTYD_INPUT:-3001}"
        set_env_value "OPENCODE_TTYD_PORT" "$TTYD_PORT"
        ok "Terminal 埠號已設定為 ${TTYD_PORT}"
    fi

    if [ -z "${VIEWER_HOST_PORT:-}" ]; then
        read -r -p "  輸入 Viewer 埠號 (Enter 使用預設 3002): " VIEWER_INPUT
        VIEWER_PORT="${VIEWER_INPUT:-3002}"
        set_env_value "VIEWER_HOST_PORT" "$VIEWER_PORT"
        ok "Viewer 埠號已設定為 ${VIEWER_PORT}"
    fi

    # Workspace volume type
    echo
    echo "  請選擇 Workspace 儲存方式:"
    echo "    1) Named Volume (預設，完全 Docker 管理)"
    echo "    2) Bind Mount ./workspace (可直接用本地 IDE 編輯)"
    if [ -n "${WORKSPACE_CHOICE:-}" ]; then
        WS_CHOICE="$WORKSPACE_CHOICE"
        echo "  選擇: $WS_CHOICE (from WORKSPACE_CHOICE env)"
    else
        read -r -p "  選擇 [1/2]: " WS_CHOICE
    fi

    case "$WS_CHOICE" in
        2)
            if [ ! -d "./workspace" ]; then
                echo "  📁 建立目錄: ./workspace"
                mkdir -p "./workspace"
            fi
            set_env_value "WORKSPACE_VOLUME_NAME" "./workspace"
            ok "使用 bind mount: ./workspace"
            ;;
        *)
            # Named volume — ensure the variable is NOT set to a path
            if grep -qE "^WORKSPACE_VOLUME_NAME=" .env 2>/dev/null; then
                sed -i '/^WORKSPACE_VOLUME_NAME=/d' .env
            fi
            ok "使用 named volume (Docker 管理)"
            ;;
    esac
}

# ──────────────────────────────────────────────────────────
# Step 5 — Pull image
# ──────────────────────────────────────────────────────────
pull_image() {
    header "5. 拉取 Docker 映像"

    echo "  拉取最新映像..."
    docker compose pull 2>&1 || warn "拉取映像失敗，將使用本地快取"
    ok "映像已就緒"
}

# ──────────────────────────────────────────────────────────
# Step 6 — Start services
# ──────────────────────────────────────────────────────────
start_services() {
    header "6. 啟動服務"

    local compose_opts=""
    if [ ! -f "docker-compose.dev.yml" ]; then
        compose_opts="-f docker-compose.yml"
    fi

    echo "  啟動容器..."
    eval "docker compose ${compose_opts} up -d 2>&1" || fail "容器啟動失敗"

    echo -n "  等待服務啟動"
    for _ in $(seq 1 30); do
        STATUS=$(docker inspect cad-workbench --format='{{.State.Status}}' 2>/dev/null)
        if [ "$STATUS" = "running" ]; then
            echo
            ok "容器已啟動"
            break
        fi
        echo -n "."
        sleep 2
    done

    echo -n "  等待服務初始化"
    sleep 10
    echo
}

# ──────────────────────────────────────────────────────────
# Step 7 — Verify
# ──────────────────────────────────────────────────────────
run_verification() {
    header "7. 驗證服務"

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
# Step 8 — Show info
# ──────────────────────────────────────────────────────────
show_info() {
    header "8. 連線資訊"

    HOST_IP=""
    if command -v ip &>/dev/null; then
        HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([^ ]*\).*/\1/p' | head -1)
    elif command -v hostname &>/dev/null; then
        HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' | grep -v '^fe80\|^::' | head -1)
    fi

    if [ -f ".env" ]; then
        # shellcheck source=/dev/null
        source .env
    fi
    TTYD_PORT="${OPENCODE_TTYD_PORT:-3001}"
    VIEWER_PORT="${VIEWER_HOST_PORT:-3002}"

    echo
    echo -e "  ${CYAN}🌐${NC} Terminal: http://${HOST_IP:-localhost}:${TTYD_PORT}"
    echo -e "  ${CYAN}🌐${NC} Viewer:   http://${HOST_IP:-localhost}:${VIEWER_PORT}"
    echo
    echo "  產生 CAD 模型:"
    echo "    docker compose exec cad-workbench bash"
    echo "    cd /opt/upstream-src && python scripts/step --help"
    echo
    echo "  升級指令: ./upgrade.sh"
    echo "  (從 upstream 拉新 compose / image，自動備份並合併 .env)"
    echo
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  安裝完成!${NC}"
    echo -e "${BOLD}========================================${NC}"
}

# ──────────────────────────────────────────────────────────
# Delegate to upgrade if already installed
# ──────────────────────────────────────────────────────────
delegate_to_upgrade_if_installed() {
    if [ ! -f "docker-compose.yml" ]; then
        return 0
    fi

    echo
    echo "========================================"
    echo "  偵測到已安裝環境"
    echo "========================================"
    echo "  - docker-compose.yml 已存在於 $(pwd)"
    echo "  - install.sh 僅供首次安裝；改執行 ./upgrade.sh"
    echo

    if [ ! -f "upgrade.sh" ]; then
        echo "  下載 upgrade.sh..."
        download_file "$REPO_URL/upgrade.sh" upgrade.sh
        chmod +x upgrade.sh
        echo "  ✅ upgrade.sh 已就緒"
    fi

    echo "  委派給 ./upgrade.sh ..."
    echo
    exec ./upgrade.sh "$@"
}

# ──────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────
main() {
    cd "$(dirname "$0")"

    delegate_to_upgrade_if_installed "$@"

    [ -t 0 ] || exec < /dev/tty

    echo
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   text-to-cad Workbench 安裝腳本     ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"

    check_system
    check_docker
    download_files
    setup_env
    pull_image
    start_services
    run_verification
    show_info
}

main "$@"
