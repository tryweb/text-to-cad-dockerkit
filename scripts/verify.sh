#!/usr/bin/env bash
set -euo pipefail

# verify.sh — Validate the cad-workbench stack startup, endpoint
# reachability, and writable persisted workspace behaviour.
#
# Usage:
#   ./scripts/verify.sh
#
# Prerequisites:
#   - docker compose up -d has succeeded
#   - .env is sourced or the same env vars are exported
#
# Exits 0 if all checks pass, non-zero otherwise.

: "${OPENCHAMBER_PORT:=3000}"
: "${VIEWER_HOST_PORT:=3002}"
: "${LOCAL_UID:=1000}"
: "${LOCAL_GID:=1000}"
SENTINEL=".verify-$(date +%s)-$$"
CAD_SMOKE_FILE="verify-$$_root.step"
CAD_SUB_DIR="verify-subdir-$$"
CAD_SUB_FILE="${CAD_SUB_DIR}/part.step"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

check_catalog_visibility() {
    local source_path="$1"
    local root_relative="$2"
    local i visible=0

    docker compose exec -T --user opencode cad-workbench sh -lc \
        "mkdir -p \"\$(dirname '${source_path}')\" && printf 'ISO-10303;' > '${source_path}'" \
        > /dev/null 2>&1 || true

    for i in 1 2 3 4 5 6 7 8 9 10; do
        if curl -sf --max-time 5 \
            "http://${HOST}:${VIEWER_HOST_PORT}/__cad/catalog?dir=%2Fworkspace%2Fmodels&file=${root_relative}" \
            2>/dev/null | grep -F "\"rootRelativeFile\":\"${root_relative}\"" > /dev/null 2>&1; then
            visible=1
            break
        fi
        sleep 1
    done

    local source_dir
    source_dir="$(dirname "${source_path}")"
    local rm_targets=("${source_path}" "/workspace/models/${root_relative}")
    if [ "${source_dir}" != "/workspace" ]; then
        rm_targets+=("${source_dir}" "/workspace/models/$(dirname "${root_relative}")")
    fi
    docker compose exec -T --user opencode cad-workbench rm -rf -f \
        "${rm_targets[@]}" 2>/dev/null || true

    [ "${visible}" -eq 1 ]
}

wait_for_http_200() {
    local url="$1"
    local attempts="$2"
    local delay="$3"
    local i
    for i in $(seq 1 "${attempts}"); do
        if curl -sf --max-time 5 "${url}" > /dev/null 2>&1; then
            return 0
        fi
        sleep "${delay}"
    done
    return 1
}

# Detect host address — localhost works on standard Docker hosts;
# inside a Docker container (DooD) we need the bridge gateway or the
# container's own IP on the Docker network.
# Uses container name "cad-workbench" directly (works regardless of project name).
HOST="localhost"

# Detect DooD: if cad-workbench runs on a bridge network and we can't
# reach it via localhost (common when another OpenChamber occupies :3000),
# fall back to the gateway or container IP.
CONTAINER_IP=$(docker inspect cad-workbench \
    --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null || true)

if [ -n "${CONTAINER_IP}" ]; then
    GATEWAY=$(docker inspect cad-workbench \
        --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' 2>/dev/null || true)
    # Try gateway first (accessible from sibling containers and most host setups)
    if [ -n "${GATEWAY}" ] && curl -sf --max-time 2 "http://${GATEWAY}:${VIEWER_HOST_PORT}/" > /dev/null 2>&1; then
        HOST="${GATEWAY}"
    elif curl -sf --max-time 2 "http://localhost:${VIEWER_HOST_PORT}/" > /dev/null 2>&1; then
        HOST="localhost"
    elif [ -n "${CONTAINER_IP}" ] && curl -sf --max-time 2 "http://${CONTAINER_IP}:${VIEWER_HOST_PORT}/" > /dev/null 2>&1; then
        HOST="${CONTAINER_IP}"
    fi
fi

echo ""
echo "=== Check 1/3: Web UI endpoint ==="
echo "Probing http://${HOST}:${OPENCHAMBER_PORT}/ ..."
if wait_for_http_200 "http://${HOST}:${OPENCHAMBER_PORT}/" 5 1; then
    pass "Web UI endpoint returned 200"
else
    fail "Web UI endpoint unreachable on port ${OPENCHAMBER_PORT}"
fi

echo ""
echo "=== Check 2/3: Viewer endpoint ==="
echo "Probing http://${HOST}:${VIEWER_HOST_PORT}/ ..."
if wait_for_http_200 "http://${HOST}:${VIEWER_HOST_PORT}/" 10 1; then
    pass "Viewer endpoint returned 200"
else
    fail "Viewer endpoint unreachable on port ${VIEWER_HOST_PORT}"
fi

echo ""
echo "Checking root CAD artifact visibility via /workspace/models catalog..."
if check_catalog_visibility "/workspace/${CAD_SMOKE_FILE}" "${CAD_SMOKE_FILE}"; then
    pass "Viewer catalog exposes root CAD artifacts through /workspace/models"
else
    fail "Viewer catalog did not expose /workspace/${CAD_SMOKE_FILE} via /workspace/models"
fi

echo ""
echo "Checking subdirectory CAD artifact visibility via /workspace/models catalog..."
if check_catalog_visibility "/workspace/${CAD_SUB_FILE}" "${CAD_SUB_FILE}"; then
    pass "Viewer catalog exposes subdirectory CAD artifacts through /workspace/models"
else
    fail "Viewer catalog did not expose /workspace/${CAD_SUB_FILE} via /workspace/models"
fi

echo ""
echo "=== Check 3/3: Writable persisted workspace ==="
echo "Writing sentinel file '${SENTINEL}' to /workspace..."

if docker compose exec -T --user opencode cad-workbench touch "/workspace/${SENTINEL}" 2>/dev/null; then
    echo "  Sentinal written. Restarting container..."
    docker compose restart cad-workbench > /dev/null 2>&1
    wait_for_http_200 "http://${HOST}:${OPENCHAMBER_PORT}/" 10 1 || true

    if docker compose exec -T --user opencode cad-workbench stat "/workspace/${SENTINEL}" > /dev/null 2>&1; then
        OWNER=$(docker compose exec -T --user opencode cad-workbench stat -c '%u:%g' "/workspace/${SENTINEL}" 2>/dev/null | tr -d '\r')
        EXPECTED="${LOCAL_UID}:${LOCAL_GID}"
        if [ "${OWNER}" = "${EXPECTED}" ]; then
            pass "Sentinel file persists after restart, owned by ${OWNER}"
        else
            fail "Sentinel owner ${OWNER} != expected ${EXPECTED}"
        fi
    else
        fail "Sentinel file disappeared after restart"
    fi
else
    fail "Could not write sentinel file to workspace"
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
