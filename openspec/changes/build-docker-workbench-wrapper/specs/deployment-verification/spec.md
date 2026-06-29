## ADDED Requirements

### Requirement: Provide startup verification workflow
The system SHALL provide a verification workflow that confirms the workbench build and startup are operational, not merely that the container process exists.

#### Scenario: Operator verifies first-time startup
- **WHEN** an operator runs `scripts/verify.sh` after `docker compose up -d` has succeeded
- **THEN** the script SHALL exit `0` only if all three health checks pass (see `Verify runtime endpoints and persistence assumptions`), and SHALL exit non-zero with a clear error message identifying which check failed otherwise

### Requirement: Verify runtime endpoints and persistence assumptions
The verification workflow SHALL check the MVP runtime assumptions that matter to operators, including endpoint availability and persisted workspace behavior.

#### Scenario: Verification checks core endpoints
- **WHEN** `scripts/verify.sh` runs against a started workbench
- **THEN** it SHALL issue HTTP `GET` requests to `http://localhost:${OPENCODE_TTYD_PORT}/` and `http://localhost:${VIEWER_HOST_PORT}/` and assert that each returns status `200` within 5 seconds; failure of either check SHALL cause the script to exit non-zero

#### Scenario: Verification checks writable output behavior
- **WHEN** `scripts/verify.sh` runs against a started workbench
- **THEN** it SHALL write a uniquely named sentinel file into `/workspace` (e.g., `.verify-<timestamp>-<pid>`), run `docker compose restart cad-workbench`, and after restart assert via `stat` that the sentinel file still exists in `/workspace` and is owned by the UID/GID reported by `LOCAL_UID`/`LOCAL_GID`

### Requirement: Document upstream refresh workflow
The repository SHALL document how operators refresh to a newer upstream release tag, including when recreating the named workspace volume is required.

#### Scenario: Operator upgrades upstream version
- **WHEN** an operator changes the `TEXT_TO_CAD_VERSION` value in `.env`
- **THEN** the `README.md` SHALL list the rebuild, verification, and conditional volume-recreation steps in order, AND SHALL explicitly state the two conditions under which the named workspace volume MUST be recreated: (a) upstream seed content changed, (b) upstream image layout under `/workspace` changed
