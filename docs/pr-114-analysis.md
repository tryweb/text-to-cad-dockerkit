# PR #114 Analysis

## Source

- Upstream repo: `earthtojake/text-to-cad`
- PR: `#114`
- Title: `feat(cad-workbench): add docker stack and switch /workspace to a named volume`
- Status at analysis time: `OPEN`
- Base branch: `develop`
- Head branch: `feat/docker-compose-environment`

## Executive Summary

PR #114 is primarily a **deployment and runtime packaging change**, not a core CAD-generation feature change.

Its value is to turn upstream `text-to-cad` into a more usable Docker-based workbench by adding:

1. A Docker Compose stack
2. A multi-stage Docker image
3. A runtime entrypoint that seeds `/workspace`
4. A switch from host bind mount to named volume
5. Port and UID/GID configuration for safer runtime behavior
6. Verification and operational documentation

## Problems the PR Solves

### 1. Host bind mount shadowing

Previous behavior mounted the host project tree directly into `/workspace`.

This causes runtime inconsistency when the host tree differs from the image-prepared tree, especially for:

- `viewer/`
- `node_modules`
- generated assets
- cached/preinstalled runtime content

### 2. Container write-permission mismatch

If container user IDs do not match host ownership, the application may fail to write generated files under `/workspace`, especially model outputs.

### 3. Weak repeatability for development/runtime setup

Without a packaged stack, users must reconstruct environment setup manually.

## Core Design Changes in the PR

## A. `/workspace` becomes a named volume

Instead of:

- host bind mount → `/workspace`

The PR changes runtime to:

- image seed → named volume → `/workspace`

Operationally:

- first boot copies image content into the volume
- later restarts preserve generated output
- source refresh requires rebuilding and/or clearing the volume

## B. Root bootstrap then privilege drop

Container starts as root so it can:

- adjust `opencode` UID/GID using `LOCAL_UID` and `LOCAL_GID`
- chown materialized workspace files
- then drop privileges and run the application stack safely

## C. Workbench-oriented runtime

The PR packages a usable runtime environment with:

- ttyd terminal endpoint
- viewer dev server
- Docker verification script
- operational docs and OpenCode skills

## Main Files Introduced or Modified

- `.docker/Dockerfile`
- `.docker/entrypoint.sh`
- `.docker/opencode.json`
- `docker-compose.yml`
- `scripts/dev/compose-verify.sh`
- `.opencode/skills/*`
- `docs/knowledge/tooling/*`

## Implications for This Repository

This PR is suitable to be **split out into an independent wrapper/deployment repository** because most of its logic belongs to the deployment layer rather than upstream product logic.

That makes it a good conceptual fit for `text-to-cad-dockerkit`.

## Constraint: Release Consumption

Current upstream release analysis shows:

- release `0.3.7` exists
- PR #114 is not merged into that release
- release assets do not include a prebuilt Docker image

Therefore, this repository cannot currently depend on an official upstream release and expect PR #114 behavior to already exist.

## Planning Conclusion

For this repository, PR #114 should be treated as a **reference design** for the deployment layer.

Recommended interpretation:

- upstream `text-to-cad` remains the application source of truth
- `text-to-cad-dockerkit` owns the Docker packaging, runtime orchestration, and deployment guidance
