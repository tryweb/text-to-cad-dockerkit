---
name: release
description: Run local tests, auto-calculate semver, generate release notes, tag, and release
---

# Release Skill

This skill automates the release process: local test validation, version bump calculation, release note generation, tagging, and pushing.

## Workflow

When the user asks to release, follow these steps in order:

### 1. Ensure the Stack Is Running (Dev Mode)

Tests require the full compose stack (with dev overlay) to be up. Check:

```bash
docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null
```

If `cad-workbench` is not running or not healthy, build and start:

```bash
echo "[release] Stack not running. Building and starting in dev mode..."
export COMPOSE_FILE=docker-compose.yml:docker-compose.dev.yml
docker compose up --build -d
```

Wait for the container to be ready:

```bash
echo "[release] Waiting for container to be ready..."
for i in $(seq 1 30); do
  STATUS=$(docker inspect cad-workbench --format='{{.State.Status}}' 2>/dev/null)
  if [ "$STATUS" = "running" ]; then
    echo "[release] Container is running."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "[release] ERROR: Container failed to start after 30s."
    docker compose logs --tail=20
    exit 1
  fi
  sleep 2
done

# Extra wait for services inside the container to initialize
sleep 10
```

### 2. Run Local Verification

```bash
export COMPOSE_FILE=docker-compose.yml:docker-compose.dev.yml
./scripts/verify.sh
```

If any check fails, stop and report the failures. Do not proceed with release.

### 3. Check for Uncommitted Changes

```bash
git status --short
```

**If there are uncommitted changes:**
1. **Ask the user** if they want to commit them before release.
2. If user confirms, create a descriptive commit message following conventional commits:
   - `feat:` for new features
   - `fix:` for bug fixes
   - `chore:` for maintenance tasks
   - `docs:` for documentation
3. **Commit before continuing** with the release.

**If working tree is clean:**
- Proceed to version determination.

Do not release with uncommitted changes. All changes must be committed before tagging.

### 4. Determine Current and Next Version

```bash
# Get latest tag
git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
```

Parse the current version (e.g., `v0.1.0`). Then analyze `git log` since the last tag to determine the bump type:

- **MAJOR** bump: if any commit contains `BREAKING CHANGE` or `!:` in the subject
- **MINOR** bump: if any commit starts with `feat:` or `feat(`
- **PATCH** bump: for `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `ci:`, `chore:`, or any other commit

Calculate the next version accordingly.

### 5. Generate Release Notes

```bash
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LAST_TAG" ]; then
  git log "${LAST_TAG}..HEAD" --oneline --no-merges
else
  git log --oneline --no-merges
fi
```

Categorize commits into sections for display to the user:

```
## Features
- descriptions

## Bug Fixes
- descriptions

## Other Changes
- descriptions
```

Strip the conventional commit prefix (e.g., `feat: `, `fix: `) for cleaner notes.

### 5.5. Update CHANGELOG (Before Tagging)

**CRITICAL**: This step must happen BEFORE tagging, not after. Create or update `docs/CHANGELOG.md` so the version changes are included in the same release.

If `docs/CHANGELOG.md` does not exist, create it with:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
```

Then for each release, create a new version section:

```bash
TODAY=$(date +%Y-%m-%d)
```

Insert a new section after `[Unreleased]`:

```markdown
## [Unreleased]

## [VERSION] - YYYY-MM-DD

### Added
### Fixed
### Changed
```

Then commit all changes together:

```bash
git add docs/CHANGELOG.md
git commit -m "docs: update CHANGELOG for v{VERSION} release"
```

This ensures the CHANGELOG changes are included in the release tag.

### 6. Confirm with User

Present the calculated version and generated release notes. Ask for confirmation before proceeding.

### 7. Tag and Push

Upon confirmation:

```bash
git tag -a v{VERSION} -m "Release v{VERSION}"
git push origin main
git push origin v{VERSION}
```

This triggers the GitHub Actions CI workflow which will:
- Build and test the image
- On tag push: push image to `ghcr.io/tryweb/text-to-cad-dockerkit`
- Create a GitHub Release with auto-generated body containing:
  - Docker pull command
  - Quick start instructions
  - Changelog since previous tag

### 8. Report

After push, inform the user:

```
Release v{VERSION} complete.

Tag: v{VERSION}
Image: ghcr.io/tryweb/text-to-cad-dockerkit:v{VERSION}
Release: https://github.com/tryweb/text-to-cad-dockerkit/releases/tag/v{VERSION}
```

## Rules

- Never skip the verification step.
- Never release with uncommitted changes (must commit first).
- Never push without user confirmation.
- If `git log` is empty since last tag, warn the user.
- Use semver format: `v{MAJOR}.{MINOR}.{PATCH}`.
- If no previous tag exists, start at `v0.1.0`.
