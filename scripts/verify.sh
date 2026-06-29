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

: "${OPENCODE_TTYD_PORT:=3001}"
: "${VIEWER_HOST_PORT:=3002}"
: "${LOCAL_UID:=1000}"
: "${LOCAL_GID:=1000}"
SENTINEL=".verify-$(date +%s)-$$"
CAD_SMOKE_FILE="verify-$$_root.step"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

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
# inside a Docker container (DooD) we need the bridge gateway.
HOST="localhost"
if ! curl -sf --max-time 2 "http://localhost:${OPENCODE_TTYD_PORT}/" > /dev/null 2>&1; then
    GATEWAY=$(docker network inspect text-to-cad-dockerkit_default \
        --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
    if [ -n "${GATEWAY}" ] && curl -sf --max-time 2 "http://${GATEWAY}:${OPENCODE_TTYD_PORT}/" > /dev/null 2>&1; then
        HOST="${GATEWAY}"
    fi
fi

echo ""
echo "=== Check 1/3: Terminal endpoint ==="
echo "Probing http://${HOST}:${OPENCODE_TTYD_PORT}/ ..."
if wait_for_http_200 "http://${HOST}:${OPENCODE_TTYD_PORT}/" 5 1; then
    pass "Terminal endpoint returned 200"
else
    fail "Terminal endpoint unreachable on port ${OPENCODE_TTYD_PORT}"
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
docker compose exec -T --user opencode cad-workbench sh -lc "printf 'ISO-10303;' > '/workspace/${CAD_SMOKE_FILE}'" > /dev/null 2>&1 || true
catalog_visible=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    CATALOG=$(curl -sf --max-time 5 "http://${HOST}:${VIEWER_HOST_PORT}/__cad/catalog?dir=%2Fworkspace%2Fmodels&file=${CAD_SMOKE_FILE}" 2>/dev/null || true)
    if printf '%s' "${CATALOG}" | grep -F "\"rootRelativeFile\":\"${CAD_SMOKE_FILE}\"" > /dev/null 2>&1; then
        catalog_visible=1
        break
    fi
    sleep 1
done

if [ "${catalog_visible}" -eq 1 ]; then
    pass "Viewer catalog exposes root CAD artifacts through /workspace/models"
else
    fail "Viewer catalog did not expose /workspace/${CAD_SMOKE_FILE} via /workspace/models"
fi

docker compose exec -T --user opencode cad-workbench rm -f \
    "/workspace/${CAD_SMOKE_FILE}" \
    "/workspace/models/${CAD_SMOKE_FILE}" > /dev/null 2>&1 || true

echo ""
echo "=== Check 3/3: Writable persisted workspace ==="
echo "Writing sentinel file '${SENTINEL}' to /workspace..."

if docker compose exec -T --user opencode cad-workbench touch "/workspace/${SENTINEL}" 2>/dev/null; then
    echo "  Sentinal written. Restarting container..."
    docker compose restart cad-workbench > /dev/null 2>&1
    wait_for_http_200 "http://${HOST}:${OPENCODE_TTYD_PORT}/" 10 1 || true

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
