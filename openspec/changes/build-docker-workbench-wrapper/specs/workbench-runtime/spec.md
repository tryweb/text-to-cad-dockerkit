## ADDED Requirements

### Requirement: Run one primary workbench container
The system SHALL run upstream text-to-cad in one primary Docker Compose-managed workbench container for MVP.

#### Scenario: Compose startup creates one workbench service
- **WHEN** an operator runs `docker compose up -d` against the repository's `docker-compose.yml`
- **THEN** exactly one service named `cad-workbench` SHALL be started, and `docker compose ps` SHALL report a single running container for that service

### Requirement: Persist workspace data in a named volume
The system SHALL mount a named volume at `/workspace` and SHALL NOT use a host bind mount as the default source of truth for that path.

#### Scenario: Restart preserves generated artifacts
- **WHEN** an operator runs `docker compose restart cad-workbench` after writing a file into `/workspace`
- **THEN** `ls /workspace` inside the restarted container SHALL list that file with no modification to its content, mtime, or ownership

#### Scenario: Host source does not shadow image-prepared files
- **WHEN** the container starts with the default runtime topology
- **THEN** `/workspace` SHALL come from the named volume rather than from a host source tree bind mount

### Requirement: Seed workspace content on first boot
The system SHALL copy seed content into `/workspace` only when the named volume is uninitialized.

#### Scenario: First boot initializes the workspace
- **WHEN** the named volume backing `/workspace` is empty (operator runs `docker volume rm <volume>` first, or uses a fresh install)
- **THEN** the entrypoint SHALL copy every file under `/opt/workspace-seed` into `/workspace` preserving the seed tree

#### Scenario: Later restarts preserve user workspace changes
- **WHEN** `/workspace` already contains at least one user-created file and the container restarts
- **THEN** the entrypoint SHALL NOT modify, delete, or overwrite any existing file in `/workspace` (verified by `find /workspace -newer /opt/workspace-seed -type f` returning at least one user file after restart)

### Requirement: Remap runtime permissions for persisted workspace access
The system SHALL support runtime user and group remapping through `LOCAL_UID` and `LOCAL_GID` before launching the application processes.

#### Scenario: Runtime user matches host ownership expectations
- **WHEN** an operator supplies `LOCAL_UID=1000` and `LOCAL_GID=1000` and starts the stack
- **THEN** `id` inside the running workbench SHALL report `uid=1000(<name>) gid=1000(<name>)` AND a file created by the workbench in `/workspace` SHALL be owned by `1000:1000` on the host (`stat -c '%u:%g' <file>`)

### Requirement: Expose terminal and viewer endpoints from the workbench
The system SHALL start the browser terminal endpoint, the viewer endpoint, and the application processes from the workbench container entrypoint.

#### Scenario: Entry point starts all MVP processes
- **WHEN** the container finishes bootstrap
- **THEN** `ss -tlnp` (or `netstat -tlnp`) inside the container SHALL show listeners on `OPENCODE_TTYD_PORT` and `VIEWER_HOST_PORT`, AND the entrypoint's process tree SHALL include one ttyd process, one viewer process, and at least one upstream application process
