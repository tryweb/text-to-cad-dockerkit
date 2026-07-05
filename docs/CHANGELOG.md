# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
