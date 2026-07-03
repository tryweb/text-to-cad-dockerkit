#!/usr/bin/env bash
set -euo pipefail

# fetch-upstream.sh — Download a pinned earthtojake/text-to-cad release archive
# outside the Docker build (for local inspection or CI pinning).
#
# Usage:
#   ./scripts/fetch-upstream.sh [version] [output-dir]
#
# Default version: pinned `TEXT_TO_CAD_VERSION` from ./Dockerfile
# Default output: ./upstream-<version>/

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_VERSION="$(sed -n 's/^ARG TEXT_TO_CAD_VERSION=//p' "${REPO_ROOT}/Dockerfile" | head -n1)"
TEXT_TO_CAD_VERSION="${1:-${TEXT_TO_CAD_VERSION:-${DEFAULT_VERSION}}}"

: "${TEXT_TO_CAD_VERSION:?Unable to resolve TEXT_TO_CAD_VERSION from argument, environment, or Dockerfile}"

OUTPUT_DIR="${2:-./upstream-${TEXT_TO_CAD_VERSION}}"
ARCHIVE_URL="https://github.com/earthtojake/text-to-cad/archive/refs/tags/${TEXT_TO_CAD_VERSION}.tar.gz"

echo "[fetch-upstream] Fetching upstream ${TEXT_TO_CAD_VERSION}..."
echo "[fetch-upstream] URL: ${ARCHIVE_URL}"

mkdir -p "${OUTPUT_DIR}"
curl -fsSL "${ARCHIVE_URL}" \
    | tar xz --strip-components=1 -C "${OUTPUT_DIR}"

echo "[fetch-upstream] Extracted to: ${OUTPUT_DIR}"
echo "[fetch-upstream] Done."
