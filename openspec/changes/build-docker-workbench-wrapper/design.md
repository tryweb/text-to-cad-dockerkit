## Context

`text-to-cad-dockerkit` is a greenfield wrapper repository whose job is to package and run upstream `earthtojake/text-to-cad` releases through a reproducible Docker workbench. Upstream PR #114 provides the reference runtime shape, but that behavior is not yet part of an official upstream release. This repository therefore needs to recreate the deployment layer locally while keeping ownership boundaries clear: upstream remains the source of truth for application code and release tags, while this repository owns containerization, runtime bootstrap, and operational verification.

The project has already converged on several architectural decisions:
- build from upstream release tags inside the Dockerfile (A-1)
- use one primary workbench container managed by Docker Compose
- use `entrypoint.sh` background processes plus `wait` instead of `supervisord`
- seed a named `/workspace` volume on first boot
- remap runtime UID/GID using `LOCAL_UID` and `LOCAL_GID`
- reimplement PR #114 deployment behavior here instead of maintaining an upstream fork

## Goals / Non-Goals

**Goals:**
- Build a reproducible image from a pinned upstream release tag with no dependency on upstream feature branches.
- Start a usable Docker workbench that exposes the terminal and viewer endpoints expected by operators.
- Preserve generated artifacts and user workspace content across restarts using a named volume.
- Avoid host/container permission mismatches by remapping the runtime user before launching application processes.
- Keep the wrapper thin enough that upstream upgrades are primarily a version-pinning and verification exercise.

**Non-Goals:**
- Maintaining a long-lived fork of upstream application logic.
- Supporting orchestrators beyond Docker Compose for MVP.
- Splitting the runtime into multiple containers before a proven need exists.
- Designing a generalized abstraction for multiple upstream forks.
- Supporting live-edit host bind-mount workflows as the default runtime model.

## Decisions

### 1. Use wrapper-repo packaging based on release tags
The image will fetch a pinned upstream release archive during Docker build rather than depending on a branch checkout or vendored fork.

**Rationale:**
- keeps this repository aligned with upstream release boundaries
- makes build inputs explicit and reproducible
- enforces the architectural rule that deployment logic lives here, not in an upstream fork

**Alternatives considered:**
- **Maintained fork:** closer to PR #114 source layout, but increases merge burden and blurs ownership
- **Wait for upstream release parity:** simpler short-term, but blocks the repository from delivering value now

### 2. Use one primary workbench container
Docker Compose will orchestrate a single `cad-workbench` service for MVP.

**Rationale:**
- matches the operational shape described in the planning docs
- avoids premature service boundaries, internal networking, and multi-container coordination
- keeps failure modes simple enough to reason about during early adoption

**Alternatives considered:**
- **Separate viewer / terminal / app containers:** more isolation, but unnecessary complexity before runtime bottlenecks are proven

### 3. Use a named volume for `/workspace`
The runtime will mount a named volume at `/workspace` and will not bind-mount the host project tree into that path.

**Rationale:**
- prevents host bind mounts from shadowing image-prepared files and dependencies
- preserves generated artifacts across restarts
- makes first-boot seeding deterministic

**Alternatives considered:**
- **Host bind mount:** convenient for live editing, but reintroduces image/runtime divergence and dependency shadowing

### 4. Seed the workspace on first boot only
The image will include seed content under `/opt/workspace-seed`. `entrypoint.sh` will copy this content into `/workspace` only when the volume is uninitialized.

**Rationale:**
- gives operators a stable initial workspace without overwriting later user-generated artifacts
- separates immutable image content from mutable working data

**Alternatives considered:**
- **Always reseed on startup:** simpler logic, but destructive to persisted workspace state

### 5. Remap runtime UID/GID before starting processes
The container will start with enough privilege to adjust the runtime user/group to `LOCAL_UID` / `LOCAL_GID`, fix workspace ownership, then drop privileges for process startup.

**Rationale:**
- prevents write failures when generated files land on persisted volumes
- follows the reference behavior described in PR #114 analysis

**Alternatives considered:**
- **Static container user:** simpler build, but unreliable across different host environments

### 6. Use `entrypoint.sh` + background processes + `wait`
The workbench container will start ttyd, viewer, and application processes from one entrypoint script using background execution and `wait`.

**Rationale:**
- avoids adding a dedicated process supervisor dependency for MVP
- keeps startup logic transparent and easy to debug

**Alternatives considered:**
- **supervisord / s6:** stronger process management, but unnecessary until restart behavior or observability gaps justify it

### 7. Treat PR #114 as a design reference, not a dependency
Implementation choices should follow PR #114's operational ideas where they fit, but all runtime files in this repository must be owned locally.

**Rationale:**
- protects this repository from upstream branch volatility
- preserves the rule that this project must work from release tags, not fork-only behavior

## Risks / Trade-offs

- **Upstream layout drift** → verify paths and install steps on each upstream version bump; keep Dockerfile assumptions minimal.
- **Named-volume refresh friction** → document when operators must recreate the workspace volume after upstream changes.
- **Multi-process container fragility** → add signal handling and exit propagation in `entrypoint.sh`; rely on Docker restart policy for MVP.
- **Build-time network dependency** → pin release URLs and surface failures clearly during image build.
- **PR #114 parity gap** → treat verification as a first-class deliverable so this repo proves runtime behavior independently of upstream merge timing.

## Migration Plan

1. Introduce container build and runtime files in this repository without modifying upstream source.
2. Pin an initial upstream release tag and verify image build reproducibility.
3. Validate first-boot workspace seeding, UID/GID remapping, terminal/viewer reachability, and artifact persistence.
4. Document operator startup and upgrade flows, including when to recreate the named volume.
5. On future upstream upgrades, change the pinned tag, rebuild, rerun verification, and recreate the workspace volume only when layout or seed assumptions change.

Rollback for early iterations is straightforward: revert the wrapper-repo files or pin back to the previous upstream release tag.

## Open Questions

None at MVP time. The following resolutions are recorded so implementation has unambiguous inputs:

- **First supported baseline tag**: the latest stable release tag published on the upstream `earthtojake/text-to-cad` repository. As a starting point, the PR #114 analysis records `0.3.7` as a known existing release; operators MUST confirm the current latest tag via `git ls-remote --tags https://github.com/earthtojake/text-to-cad` before pinning `TEXT_TO_CAD_VERSION`. The first supported tag becomes a concrete value only at the moment of the first successful image build and is then committed to `.env.example` as the documented default.
- **Viewer and application startup contract**: treated as best-effort discovery. The wrapper does NOT hardcode upstream startup commands. Instead, the `Dockerfile` and `entrypoint.sh` discover the contract from the upstream source tree at build/runtime time (e.g., `package.json` scripts, upstream `README.md`, or upstream `docker-compose.yml` if present). Discovery output is logged at container start. Operators are responsible for verifying the discovered commands in the first verification run.
- **Minimal health checks for `scripts/verify.sh`**: three assertions, all must pass for a successful verification:
  1. HTTP probe to the terminal endpoint (`http://localhost:${OPENCODE_TTYD_PORT}/`) returns `200` within 5 seconds.
  2. HTTP probe to the viewer endpoint (`http://localhost:${VIEWER_HOST_PORT}/`) returns `200` within 5 seconds.
  3. A sentinel file written to `/workspace` by the verification script survives a `docker compose restart cad-workbench` (verified by `stat` showing the file still exists and belongs to the remapped UID/GID).
