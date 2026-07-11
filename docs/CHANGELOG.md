# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.0.0] - 2026-07-11

### Added
- Replace ttyd web terminal with OpenChamber (@openchamber/web) full web UI
- Seed OpenChamber with `/workspace` as the default project on first launch
- Persist OpenChamber settings (projects, theme) across container restarts via `openchamber-config` volume
- Auto-detect Docker bridge gateway in `verify.sh` for Docker-out-of-Docker dev environments
- Mirror CAD artifact parent directories with opencode user ownership in `sync_cad_artifacts` so `verify.sh` cleanup can remove them

### Changed
- Bump `@openchamber/web` 1.14.1 → 1.15.0 (per-project default model, non-ASCII path fix)
- Bump `text-to-cad` 0.3.8 → 0.3.9, `lean-ctx` 3.9.5 → 3.9.6, `opencode-ai` stays at 1.17.18, base image Ubuntu 24.04, Python 3.12
- Web UI port 3001 → 3000 (matches OpenChamber default)
- `start_ttyd` → `start_openchamber` (foreground mode, `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN` for LAN access)
- Rename `OPENCODE_TTYD_PORT` → `OPENCHAMBER_PORT` and `TTYD_PORT` → `CHAMBER_PORT` across `install.sh` / `upgrade.sh` / `.env.example`
- `verify.sh` cleanup now removes parent test directories (guarded so `/workspace` itself is never removed)
- README / docs updated to reference OpenChamber instead of ttyd

## [0.3.0] - 2026-07-10

### Added
- Integrate lean-ctx context engineering tool

### Changed
- Update OPENCODE_AI_VERSION to 1.17.18
- Update upstream pinned dependencies
- Add demo video links to README

## [0.2.0] - 2026-07-05

### Added
- Add WORKSPACE_CHOICE env var for non-interactive install
- Add install/upgrade scripts and update README

### Fixed
- Upgrade create-pull-request to v8 for Node.js 24 compat
- Use compact jq output for GITHUB_OUTPUT multi-line compat
- Replace all grep -oP with POSIX-compatible sed for BusyBox compat
- Replace grep -oP with sed for BusyBox compat in show_info
- Lower RAM requirement to 3 GB (single-container vs multi-service)
- Use KB-level RAM comparison to avoid integer truncation
- Handle BusyBox wget compat in install/upgrade scripts

### Changed
- Update upstream pinned dependencies
- Update image path to ghcr.io/tryweb/text-to-cad-dockerkit
- Rewrite upstream-update.yml for multi-ARG version tracking

## [0.1.0] - 2026-07-03

### Added
- Split docker-compose into production and dev files
- Add CI workflow for build, test, push, and release
- Add compose runtime bootstrap
- Add Docker build wrapper files
- Mirror CAD artifacts recursively, preserving subdirectory layout
- Preinstall Chromium and npm in runtime stage
- Auto-restart CAD Viewer when new CAD files are detected
- Persist opencode auth, config, and cache across container restarts
- Pin build-time versions in Dockerfile
- Add release skill

### Fixed
- Fix gateway detection in verify.sh for CI compat

### Changed
- Update README for dev/production workflow and CI/CD docs
- Remove runtime version pinning
