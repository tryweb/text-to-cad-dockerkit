## 1. Build and source packaging

- [x] 1.1 Create `Dockerfile` that fetches a pinned upstream `earthtojake/text-to-cad` release archive during image build.
- [x] 1.2 Install the upstream Python and viewer dependencies during image build and stage the upstream source under the image runtime paths.
- [x] 1.3 Add `.env.example` with the required version, UID/GID, and port configuration variables.
- [x] 1.4 Add `scripts/fetch-upstream.sh` so operators can download the same pinned upstream archive outside the Docker build (e.g., for local inspection or CI pinning). Verify: the script downloads the archive referenced by `TEXT_TO_CAD_VERSION` and exits non-zero on HTTP failure.

## 2. Runtime bootstrap and compose topology

- [x] 2.1 Create `entrypoint.sh` to seed `/workspace` on first boot, remap the runtime user/group from `LOCAL_UID` / `LOCAL_GID`, and prepare writable output paths.
- [x] 2.2 Add multi-process startup logic in `entrypoint.sh` for ttyd, viewer, and application processes using background execution plus `wait`, with `trap`-based signal forwarding so SIGTERM/SIGINT from Docker stop reaches the children and the container exits with the first child's exit code.
- [x] 2.3 Create `docker-compose.yml` with one primary workbench service, named-volume `/workspace` persistence, and terminal/viewer port mappings.

## 3. Verification and operator workflow

- [x] 3.1 Create `scripts/verify.sh` to validate image startup, terminal/viewer reachability, and writable persisted workspace behavior.
- [x] 3.2 Write `README.md` usage instructions for first-time startup, verification, and upstream version refresh.
- [x] 3.3 Document when operators must recreate the named workspace volume after upstream version changes or seed-content changes.

## 4. Validation and refinement

- [x] 4.1 Build the image against the initial pinned upstream release tag and resolve any path or dependency drift.
- [x] 4.2 Run the Compose stack and confirm first-boot workspace seeding, UID/GID remapping, and artifact persistence across restart.
- [x] 4.3 Run the verification workflow end to end and update documentation or bootstrap logic to match the proven runtime behavior.
