# Target Architecture

## Goal

Create a dedicated wrapper repository that runs upstream `earthtojake/text-to-cad` through a reproducible Docker-based workbench, while keeping deployment logic separate from upstream application logic.

## Architecture Decision

Use a **wrapper-repo architecture**.

- Upstream repo owns application code and release tags
- This repo owns containerization and deployment workflows

## Recommended Responsibility Boundaries

### Upstream `text-to-cad`

Owns:

- CAD generation logic
- Python/package dependencies specific to the app
- viewer source
- upstream release tags and source layout

### `text-to-cad-dockerkit`

Owns:

- Dockerfile
- Docker Compose topology
- container entrypoint
- workspace seeding strategy
- UID/GID remapping strategy
- ports and environment configuration
- verification scripts
- deployment and operational documentation

## Recommended Runtime Shape

```text
Host
└─ docker compose up
   └─ cad-workbench container
      ├─ /opt/upstream-src        # baked upstream release source
      ├─ /opt/workspace-seed      # image seed content
      ├─ /workspace               # named volume mounted at runtime
      ├─ ttyd                     # browser terminal endpoint
      ├─ viewer                   # browser viewer endpoint
      └─ models output            # persisted generated artifacts
```

## Container Lifecycle

1. Build image from pinned upstream version
2. Bake upstream source and dependencies into image
3. On first boot, copy seed content into `/workspace`
4. Remap runtime user with `LOCAL_UID` / `LOCAL_GID`
5. Ensure output directories are writable
6. Start terminal/viewer/application processes

## Data and Persistence Model

### Named volume for `/workspace`

Recommended default:

- use named volume for `/workspace`
- do not bind mount host project source into `/workspace`

Rationale:

- avoids image/runtime tree divergence
- protects preinstalled dependencies from host shadowing
- preserves generated artifacts between restarts

### Generated output

Expected outputs should persist in the named volume, especially:

- CAD model files
- intermediate workspace files
- user-generated artifacts

## Configuration Model

Recommended environment variables:

- `LOCAL_UID`
- `LOCAL_GID`
- `OPENCODE_TTYD_PORT`
- `VIEWER_HOST_PORT`

Pinned build-time component versions should live in `Dockerfile`, not runtime
environment files.

Optional future variables:

- `WORKSPACE_VOLUME_NAME`
- `MODELS_SUBDIR`
- `UPSTREAM_ARCHIVE_URL`

## Repository Layout Recommendation

```text
text-to-cad-dockerkit/
├─ docs/
├─ docker-compose.yml
├─ Dockerfile
├─ entrypoint.sh
├─ .env.example
├─ scripts/
│  ├─ fetch-upstream.sh
│  └─ verify.sh
└─ README.md
```

## Non-Goals for MVP

Do not add these unless a real need appears:

- custom orchestration platform support beyond Docker Compose
- multi-container microservice split without a proven runtime need
- speculative abstraction for multiple upstream forks
- complicated live-edit sync workflows

## Architecture Recommendation

For MVP, use **one primary workbench container** managed by Docker Compose.

This is the simplest shape that preserves PR #114's operational benefits without over-designing the wrapper repository.
