# text-to-cad-dockerkit

Docker workbench wrapper for [earthtojake/text-to-cad](https://github.com/earthtojake/text-to-cad).

Build a reproducible Docker workbench from pinned upstream release tags. Run CAD
generation, browse models with the CAD Viewer, and access a browser terminal —
all from one `docker compose` command.

## Prerequisites

- Docker Engine 24+ with Compose V2 plugin
- Git (for version tracking, not required at runtime)

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env: set LOCAL_UID / LOCAL_GID to match your host user
#   (run `id -u` and `id -g` to see yours)

# 2. Build the image
docker compose build

# 3. Start the stack
docker compose up -d

# 4. Verify everything works
./scripts/verify.sh

# 5. Open in browser
# Terminal: http://localhost:3001
# Viewer:   http://localhost:3002
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `TEXT_TO_CAD_VERSION` | `0.3.7` | Upstream release tag to build from |
| `LOCAL_UID` | `1000` | Host user UID for workspace file ownership |
| `LOCAL_GID` | `1000` | Host user GID for workspace file ownership |
| `OPENCODE_TTYD_PORT` | `3001` | Host port for the browser terminal |
| `VIEWER_HOST_PORT` | `3002` | Host port for the CAD Viewer |
| `WORKSPACE_VOLUME_NAME` | `cad-workbench-workspace` | Named volume for `/workspace` persistence |

## Usage

### Terminal access

Open [http://localhost:3001](http://localhost:3001) in your browser. You get a
shell inside the workbench container with the upstream source tree at
`/opt/upstream-src` and your persistent workspace at `/workspace`.

### CAD Viewer

Open [http://localhost:3002](http://localhost:3002) to preview STEP, STL, 3MF,
and other model files.

The viewer catalog is rooted at `/workspace/models`. Root-level CAD artifacts
written to `/workspace` are automatically mirrored into `/workspace/models` so
they remain visible in the viewer without changing the generating workflow.

### Generating models

```bash
# Enter the container
docker compose exec cad-workbench bash

# Run CAD generation from the upstream source tree
cd /opt/upstream-src
python scripts/step --help
```

Generated models persist in `/workspace/models` and `/workspace/output`.

### Artifact layout convention

- `/workspace/models` is the canonical viewer-visible CAD artifact directory.
- If a tool writes supported CAD files directly under `/workspace` (for example
  `table.step`), the entrypoint mirrors them into `/workspace/models`.
- This keeps viewer discovery consistent while preserving the original root file.

## Upgrading to a new upstream version

```bash
# 1. Check the latest release
git ls-remote --tags https://github.com/earthtojake/text-to-cad

# 2. Update the version
#    Edit .env and change TEXT_TO_CAD_VERSION

# 3. Rebuild the image
docker compose build --no-cache

# 4. Recreate the workspace volume (only if seed content or layout changed)
docker compose down -v
docker compose up -d

# 5. Verify
./scripts/verify.sh
```

## When to recreate the workspace volume

The named volume at `/workspace` persists across restarts. Recreate it when:

1. **Upstream seed content changed** — the `/opt/workspace-seed` directory in the
   new image contains updated benchmark files, scripts, or documentation that you
   want in your workspace.
2. **Upstream layout changed** — the new release expects files or directories
   under `/workspace` that the old volume does not have.

To recreate:

```bash
docker compose down -v    # stops containers AND removes the named volume
docker compose up -d      # creates a fresh volume with new seed content
```

> **Warning**: `docker compose down -v` destroys all files in `/workspace`.
> Back up any generated models or output files first.

## Project structure

```
text-to-cad-dockerkit/
├── Dockerfile              # Multi-stage image build from upstream release
├── docker-compose.yml      # Workbench service topology
├── entrypoint.sh           # Container entrypoint (seeding, remap, process mgmt)
├── .env.example            # Environment variable template
├── scripts/
│   ├── fetch-upstream.sh   # Download upstream release outside Docker build
│   └── verify.sh           # Post-startup verification workflow
└── README.md
```

## Architecture

This is a thin deployment wrapper. Upstream `earthtojake/text-to-cad` owns:

- CAD generation logic and Python/Node dependencies
- Viewer source code
- Release tags and source layout

This repository owns:

- Docker packaging and multi-stage build
- Docker Compose topology
- Container entrypoint and workspace seeding
- UID/GID remapping and port configuration
- Verification scripts and operational documentation

See [docs/target-architecture.md](docs/target-architecture.md) for details.
