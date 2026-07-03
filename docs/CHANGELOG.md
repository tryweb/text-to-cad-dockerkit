# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
