#!/usr/bin/env bash
set -euo pipefail

# fetch-upstream.sh — Download a pinned earthtojake/text-to-cad release archive
# outside the Docker build (for local inspection or CI pinning).
#
# Usage:
#   TEXT_TO_CAD_VERSION=0.3.7 ./scripts/fetch-upstream.sh [--output-dir <dir>]
#
# Default output: ./upstream-<version>/

: "${TEXT_TO_CAD_VERSION:?Set TEXT_TO_CAD_VERSION to the upstream release tag}"

OUTPUT_DIR="${1:-./upstream-${TEXT_TO_CAD_VERSION}}"
ARCHIVE_URL="https://github.com/earthtojake/text-to-cad/archive/refs/tags/${TEXT_TO_CAD_VERSION}.tar.gz"

echo "[fetch-upstream] Fetching upstream ${TEXT_TO_CAD_VERSION}..."
echo "[fetch-upstream] URL: ${ARCHIVE_URL}"

mkdir -p "${OUTPUT_DIR}"
curl -fsSL "${ARCHIVE_URL}" \
    | tar xz --strip-components=1 -C "${OUTPUT_DIR}"

echo "[fetch-upstream] Extracted to: ${OUTPUT_DIR}"
echo "[fetch-upstream] Done."
