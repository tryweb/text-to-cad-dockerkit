#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# text-to-cad-dockerkit — workbench container entrypoint
#
# Responsibilities:
#   1. Seed /workspace from /opt/workspace-seed on first boot
#   2. Remap runtime UID/GID to LOCAL_UID / LOCAL_GID
#   3. Ensure writable output directories
#   4. Start ttyd, viewer, and application processes
#   5. Forward SIGTERM/SIGINT and exit with first child's code
# ============================================================

# --- Configuration defaults --------------------------------------------
: "${LOCAL_UID:=1000}"
: "${LOCAL_GID:=1000}"
: "${OPENCODE_TTYD_PORT:=3001}"
: "${VIEWER_HOST_PORT:=3002}"
: "${UPSTREAM_SRC:=/opt/upstream-src}"
: "${WORKSPACE_SEED:=/opt/workspace-seed}"
: "${WORKSPACE:=/workspace}"

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

sync_root_cad_artifacts() {
    mkdir -p "${CAD_VIEWER_ROOT}"

    local source_path artifact_name target_path
    for source_path in "${WORKSPACE}"/* "${WORKSPACE}"/.*; do
        artifact_name=$(basename "${source_path}")

        if [ ! -e "${source_path}" ]; then
            continue
        fi

        if [ "${source_path}" = "${CAD_VIEWER_ROOT}" ] || [ "${artifact_name}" = "." ] || [ "${artifact_name}" = ".." ]; then
            continue
        fi

        if [ ! -f "${source_path}" ] || ! is_root_cad_artifact "${artifact_name}"; then
            continue
        fi

        target_path="${CAD_VIEWER_ROOT}/${artifact_name}"
        if [ -L "${target_path}" ]; then
            rm -f "${target_path}"
        fi

        if [ -f "${target_path}" ] && cmp -s "${source_path}" "${target_path}"; then
            continue
        fi

        cp -f "${source_path}" "${target_path}"
        chown "${LOCAL_UID}:${LOCAL_GID}" "${target_path}" 2>/dev/null || true
        echo "[entrypoint]   mirrored CAD artifact into models/: ${artifact_name}"
    done
}

start_artifact_sync_loop() {
    sync_root_cad_artifacts
    (
        while true; do
            sleep 2
            sync_root_cad_artifacts
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

# --- 4. Start child processes ------------------------------------------
pids=()

start_ttyd() {
    if command -v ttyd &>/dev/null; then
        echo "[entrypoint] Starting ttyd on port ${OPENCODE_TTYD_PORT}..."
        if command -v opencode &>/dev/null; then
            ttyd --port "${OPENCODE_TTYD_PORT}" \
                 --writable \
                 --client-option "disableLeaveAlert=true" \
                 opencode &
        else
            ttyd --port "${OPENCODE_TTYD_PORT}" \
                 --writable \
                 --client-option "disableLeaveAlert=true" \
                 bash &
        fi
        pids+=($!)
    else
        echo "[entrypoint] WARNING: ttyd not found — terminal endpoint unavailable."
    fi
}

start_viewer() {
    local viewer_dir="${UPSTREAM_SRC}/skills/cad-viewer/scripts/viewer"
    if [ -f "${viewer_dir}/backend/server.mjs" ]; then
        echo "[entrypoint] Starting CAD Viewer on port ${VIEWER_HOST_PORT} (root ${CAD_VIEWER_ROOT})..."
        cd "${viewer_dir}"
        NODE_ENV=production node backend/server.mjs \
            --host 0.0.0.0 \
            --port "${VIEWER_HOST_PORT}" \
            --dir "${CAD_VIEWER_ROOT}" &
        pids+=($!)
        cd /
    else
        echo "[entrypoint] WARNING: Viewer server.mjs not found — viewer unavailable."
    fi
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
start_artifact_sync_loop

start_ttyd
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
echo "[entrypoint] Terminal:  http://localhost:${OPENCODE_TTYD_PORT}"
echo "[entrypoint] Viewer:    http://localhost:${VIEWER_HOST_PORT}"

# Wait for any child to exit, then propagate
set +e
wait -n "${pids[@]}" 2>/dev/null || wait
exit_code=$?
set -e

echo "[entrypoint] A child process exited with code ${exit_code} — shutting down."
handle_signal TERM
exit "${exit_code}"
