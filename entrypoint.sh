#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# text-to-cad-dockerkit — workbench container entrypoint
#
# Responsibilities:
#   1. Seed /workspace from /opt/workspace-seed on first boot
#   2. Remap runtime UID/GID to LOCAL_UID / LOCAL_GID
#   3. Ensure writable output directories
#   4. Start OpenChamber, viewer, and application processes
#   5. Forward SIGTERM/SIGINT and exit with first child's code
# ============================================================

# --- Configuration defaults --------------------------------------------
: "${LOCAL_UID:=1000}"
: "${LOCAL_GID:=1000}"
: "${OPENCHAMBER_PORT:=3000}"
: "${VIEWER_HOST_PORT:=3002}"
: "${UPSTREAM_SRC:=/opt/upstream-src}"
: "${WORKSPACE_SEED:=/opt/workspace-seed}"
: "${WORKSPACE:=/workspace}"
: "${OPENCODE_HOME:=/home/opencode}"
: "${OPENCODE_CONFIG_DIR:=${OPENCODE_HOME}/.config/opencode}"
: "${LEAN_CTX_CONFIG_DIR:=${OPENCODE_HOME}/.config/lean-ctx}"

CAD_VIEWER_ROOT_RELATIVE="models"
CAD_VIEWER_ROOT="${WORKSPACE}/${CAD_VIEWER_ROOT_RELATIVE}"

is_root_cad_artifact() {
    local name="$1"
    case "${name}" in
        *.step|*.stp|*.stl|*.3mf|*.glb|*.gcode|*.dxf|*.urdf|*.srdf|*.sdf)
            return 0
            ;;
        .*.step.glb|.*.stp.glb|.*.step.js|.*.stp.js)
            return 0
            ;;
    esac
    return 1
}

sync_cad_artifacts() {
    local mirror_max_depth=3
    local mirror_exclude_paths=(
        "${CAD_VIEWER_ROOT}/*"
        "*/.opencode/*"
        "*/.git/*"
        "*/__pycache__/*"
        "*/node_modules/*"
    )
    local find_excludes=()
    local p
    for p in "${mirror_exclude_paths[@]}"; do
        find_excludes+=( -not -path "$p" )
    done

    mkdir -p "${CAD_VIEWER_ROOT}"

    local source_path rel_path target_path
    while IFS= read -r -d '' source_path; do
        rel_path="${source_path#${WORKSPACE}/}"

        if [ ! -f "${source_path}" ] || ! is_root_cad_artifact "$(basename "${source_path}")"; then
            continue
        fi

        target_path="${CAD_VIEWER_ROOT}/${rel_path}"
        mkdir -p "$(dirname "${target_path}")"
        chown "${LOCAL_UID}:${LOCAL_GID}" "$(dirname "${target_path}")" 2>/dev/null || true

        if [ -L "${target_path}" ]; then
            rm -f "${target_path}"
        fi

        if [ -f "${target_path}" ] && cmp -s "${source_path}" "${target_path}" ]; then
            continue
        fi

        cp -f "${source_path}" "${target_path}"
        chown "${LOCAL_UID}:${LOCAL_GID}" "${target_path}" 2>/dev/null || true
        echo "[entrypoint]   mirrored CAD artifact into models/: ${rel_path}"
    done < <(find "${WORKSPACE}" -mindepth 1 -maxdepth "${mirror_max_depth}" -type f \
        "${find_excludes[@]}" \
        -print0)
}

start_artifact_sync_loop() {
    sync_cad_artifacts
    (
        local prev_count
        prev_count=$(find "${CAD_VIEWER_ROOT}" -type f 2>/dev/null | wc -l)
        while true; do
            sleep 2
            sync_cad_artifacts
            local new_count
            new_count=$(find "${CAD_VIEWER_ROOT}" -type f 2>/dev/null | wc -l)
            if [ "$new_count" -gt "$prev_count" ]; then
                restart_viewer
                prev_count=$new_count
            fi
        done
    ) &
    pids+=($!)
}

# --- 1. First-boot workspace seeding -----------------------------------
seed_workspace() {
    if [ ! -f "${WORKSPACE}/.workspace-initialised" ]; then
        echo "[entrypoint] First boot — seeding /workspace from ${WORKSPACE_SEED}..."
        if [ -d "${WORKSPACE_SEED}" ]; then
            cp -r "${WORKSPACE_SEED}/." "${WORKSPACE}/" 2>/dev/null || true
        fi
        mkdir -p "${WORKSPACE}/models" "${WORKSPACE}/output"

        # Seed opencode CAD skills from upstream (symlinks to /opt/upstream-src/skills/*)
        mkdir -p "${WORKSPACE}/.opencode/skills"
        for skill_dir in /opt/upstream-src/skills/*/; do
            skill_name=$(basename "${skill_dir}")
            if [ ! -L "${WORKSPACE}/.opencode/skills/${skill_name}" ]; then
                ln -sf "${skill_dir}" "${WORKSPACE}/.opencode/skills/${skill_name}"
                echo "[entrypoint]   symlinked skill: ${skill_name}"
            fi
        done
        chown -R "${LOCAL_UID}:${LOCAL_GID}" "${WORKSPACE}/.opencode"

        touch "${WORKSPACE}/.workspace-initialised"
        echo "[entrypoint] Workspace seeded."
    else
        echo "[entrypoint] Workspace already initialised — skipping seed."
    fi
}

# --- 2. UID/GID remapping ----------------------------------------------
remap_user() {
    local current_uid current_gid
    current_uid=$(id -u opencode 2>/dev/null || echo "1000")
    current_gid=$(id -g opencode 2>/dev/null || echo "1000")

    if [ "${current_uid}" -ne "${LOCAL_UID}" ] || [ "${current_gid}" -ne "${LOCAL_GID}" ]; then
        echo "[entrypoint] Remapping opencode user to ${LOCAL_UID}:${LOCAL_GID}..."

        groupadd --force --gid "${LOCAL_GID}" opencode 2>/dev/null || true
        usermod --uid "${LOCAL_UID}" --gid "${LOCAL_GID}" opencode 2>/dev/null || true

        # Fix ownership of workspace and home
        chown -R "${LOCAL_UID}:${LOCAL_GID}" "${WORKSPACE}" 2>/dev/null || true
        chown -R "${LOCAL_UID}:${LOCAL_GID}" "/home/opencode" 2>/dev/null || true
    else
        echo "[entrypoint] UID/GID already match — no remap needed."
    fi
}

# --- 3. Ensure writable output paths -----------------------------------
ensure_writable_paths() {
    mkdir -p "${CAD_VIEWER_ROOT}" "${WORKSPACE}/output"
    chown "${LOCAL_UID}:${LOCAL_GID}" "${WORKSPACE}" 2>/dev/null || true
    chown "${LOCAL_UID}:${LOCAL_GID}" "${CAD_VIEWER_ROOT}" "${WORKSPACE}/output" 2>/dev/null || true
}

init_lean_ctx() {
    if ! command -v lean-ctx &>/dev/null; then
        echo "[entrypoint] lean-ctx not found — skipping integration setup."
        return
    fi

    mkdir -p \
        "${OPENCODE_CONFIG_DIR}" \
        "${LEAN_CTX_CONFIG_DIR}" \
        "${OPENCODE_HOME}/.local/share/lean-ctx" \
        "${OPENCODE_HOME}/.local/state/lean-ctx" \
        "${OPENCODE_HOME}/.cache/lean-ctx"

    HOME="${OPENCODE_HOME}" lean-ctx setup --non-interactive --yes >/dev/null 2>&1 || true
    HOME="${OPENCODE_HOME}" lean-ctx init --agent opencode >/dev/null 2>&1 || true

    rm -f "${OPENCODE_CONFIG_DIR}/opencode.json"
    HOME="${OPENCODE_HOME}" opencode mcp add lean-ctx -- lean-ctx >/dev/null 2>&1 || true

    chown -R "${LOCAL_UID}:${LOCAL_GID}" "${OPENCODE_HOME}" 2>/dev/null || true
    echo "[entrypoint] lean-ctx configured for opencode."
}

init_openchamber() {
    local oc_config="${OPENCODE_HOME}/.config/openchamber"
    local oc_settings="${oc_config}/settings.json"
    local workspace_id
    workspace_id="path_$(printf '%s' "${WORKSPACE}" | base64 -w0)"

    if [ -f "${oc_settings}" ]; then
        return
    fi

    mkdir -p "${oc_config}"
    chown "${LOCAL_UID}:${LOCAL_GID}" "${oc_config}"

    local now_ms
    now_ms=$(date +%s)000

    cat > "${oc_settings}" <<EOF
{
  "lastDirectory": "${WORKSPACE}",
  "homeDirectory": "${WORKSPACE}",
  "projects": [
    {
      "id": "${workspace_id}",
      "path": "${WORKSPACE}",
      "addedAt": ${now_ms},
      "lastOpenedAt": ${now_ms}
    }
  ],
  "activeProjectId": "${workspace_id}"
}
EOF
    chown "${LOCAL_UID}:${LOCAL_GID}" "${oc_settings}"
    echo "[entrypoint] OpenChamber default project seeded: ${WORKSPACE}"
}

# --- 4. Start child processes ------------------------------------------
pids=()

start_openchamber() {
    if command -v openchamber &>/dev/null; then
        echo "[entrypoint] Starting OpenChamber on port ${OPENCHAMBER_PORT}..."
        export OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true
        openchamber serve --port "${OPENCHAMBER_PORT}" --host 0.0.0.0 --foreground &
        pids+=($!)
    else
        echo "[entrypoint] WARNING: openchamber not found — web UI unavailable."
    fi
}

start_viewer() {
    local viewer_dir="${UPSTREAM_SRC}/skills/cad-viewer/scripts/viewer"
    if [ ! -f "${viewer_dir}/backend/server.mjs" ]; then
        echo "[entrypoint] WARNING: Viewer server.mjs not found — viewer unavailable."
        return
    fi
    echo "[entrypoint] Starting CAD Viewer on port ${VIEWER_HOST_PORT} (root ${CAD_VIEWER_ROOT})..."
    cd "${viewer_dir}"
    NODE_ENV=production node backend/server.mjs \
        --host 0.0.0.0 \
        --port "${VIEWER_HOST_PORT}" \
        --dir "${CAD_VIEWER_ROOT}" &
    local pid=$!
    echo "$pid" > /tmp/viewer.pid
    pids+=("$pid")
    cd /
}

restart_viewer() {
    local old_pid
    old_pid=$(cat /tmp/viewer.pid 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        echo "[entrypoint] Restarting CAD Viewer (PID $old_pid) to refresh catalog..."
        kill "$old_pid" 2>/dev/null
        wait "$old_pid" 2>/dev/null || true
    fi
    start_viewer
}

# --- Signal handler ----------------------------------------------------
handle_signal() {
    local sig="$1"
    echo "[entrypoint] Received ${sig}, forwarding to children (${pids[*]})..."
    for pid in "${pids[@]}"; do
        kill "-${sig}" "${pid}" 2>/dev/null || true
    done
}

# --- Main --------------------------------------------------------------
seed_workspace
remap_user
ensure_writable_paths
init_lean_ctx
init_openchamber
start_artifact_sync_loop

start_openchamber
start_viewer

# Discover and log upstream startup contract
echo "[entrypoint] Upstream source at: ${UPSTREAM_SRC}"
echo "[entrypoint] Workspace at: ${WORKSPACE}"

if [ "${#pids[@]}" -eq 0 ]; then
    echo "[entrypoint] ERROR: no child processes started — exiting."
    exit 1
fi

# Set up signal trapping (must be after child start to avoid race)
trap 'handle_signal TERM' TERM
trap 'handle_signal INT' INT
trap 'handle_signal QUIT' QUIT

echo "[entrypoint] Running with PIDs: ${pids[*]}"
echo "[entrypoint] Web UI:    http://localhost:${OPENCHAMBER_PORT}"
echo "[entrypoint] Viewer:    http://localhost:${VIEWER_HOST_PORT}"

# Wait for any child to exit, then propagate
set +e
wait -n "${pids[@]}" 2>/dev/null || wait
exit_code=$?
set -e

echo "[entrypoint] A child process exited with code ${exit_code} — shutting down."
handle_signal TERM
exit "${exit_code}"
