## Why

This repository exists to make upstream `earthtojake/text-to-cad` runnable as a reproducible Docker workbench without coupling deployment logic to upstream feature branches or maintaining a long-lived fork. The project needs a concrete MVP architecture now because upstream PR #114 is still only a reference design, not a released runtime contract.

## What Changes

- Add a Docker-based wrapper architecture that builds from pinned upstream release tags instead of upstream branches or forks.
- Add a single-container Docker Compose workbench runtime with a named `/workspace` volume.
- Add runtime bootstrap behavior for first-boot workspace seeding, UID/GID remapping, writable output paths, and multi-process startup via `entrypoint.sh`.
- Add configuration and verification artifacts for build, startup, and upgrade flows.
- Add explicit architectural guardrails that keep this repository as a thin deployment wrapper rather than an application fork.

## MVP Scope

For this change, "MVP" means: one Docker Compose service (`cad-workbench`), one pinned upstream release tag (operator-supplied via `TEXT_TO_CAD_VERSION`), terminal and viewer endpoints reachable from the host, a passing `scripts/verify.sh`, and `README.md` documenting first-time startup and version refresh. Multi-container topologies, live-edit bind mounts, multi-fork abstraction, and orchestrators beyond Docker Compose are out of scope.

## Capabilities

### New Capabilities
- `upstream-release-packaging`: Build the workbench image from a pinned upstream release tag fetched during Docker image build.
- `workbench-runtime`: Run upstream text-to-cad in one primary workbench container with named-volume workspace persistence, permission remapping, and browser-accessible terminal/viewer processes.
- `deployment-verification`: Provide operator-facing verification steps and scripts for startup, health checks, and upstream version refresh workflows.

### Modified Capabilities
- None.

## Impact

- Affected systems: Docker image build, Docker Compose topology, runtime bootstrap, workspace persistence, operator configuration, and deployment documentation.
- Expected files: `Dockerfile`, `docker-compose.yml`, `entrypoint.sh`, `.env.example`, `scripts/verify.sh`, `scripts/fetch-upstream.sh`, and `README.md`.
- Dependencies: upstream GitHub release archives, Python and Node package installation during image build, and runtime environment variables for UID/GID and ports.
