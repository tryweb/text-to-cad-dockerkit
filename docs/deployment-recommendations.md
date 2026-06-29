# Deployment Recommendations

## Objective

Run upstream `earthtojake/text-to-cad` releases from this repository with a maintainable deployment layer, without tightly coupling this repo to upstream feature branches.

## Evaluated Options

## Option A — Wrapper repo builds from upstream release source

### Description

This repository downloads or vendors a pinned upstream release/tag during image build, then layers Docker runtime behavior on top.

### Pros

- clear separation of concerns
- easy to pin to official upstream versions
- no long-lived fork required
- aligned with the purpose of a `dockerkit` repository

### Cons

- this repo must maintain Docker/runtime glue
- may require adjustment when upstream file layout changes
- cannot rely on unreleased PR behavior being present in official releases

### Assessment

**Recommended default approach.**

## Option B — Maintain a fork of upstream with Docker workbench branch

### Description

Keep Docker workbench logic in a maintained fork and sync with upstream over time.

### Pros

- closest to upstream runtime assumptions
- easiest path if immediate adoption of PR #114 behavior is required

### Cons

- ongoing merge/sync burden
- ownership boundary becomes blurry
- harder to keep the wrapper repo independent

### Assessment

Useful as a temporary bridge, but not the preferred long-term operating model.

## Option C — Wait for future upstream release to absorb PR #114

### Description

Do nothing now except wait until upstream merges the PR and publishes a release that includes it.

### Pros

- lowest short-term implementation effort
- cleanest dependency story if upstream ships exactly what is needed

### Cons

- timeline depends entirely on upstream
- blocks this repository from becoming useful now
- still may not provide the exact deployment contract needed here

### Assessment

Not recommended if this repository is expected to deliver value now.

## Recommended Deployment Strategy

Adopt **Option A** for MVP:

1. Pin a known upstream version/tag
2. Build a local image around that version
3. Implement Docker runtime behavior in this repository
4. Use PR #114 as a design reference, not as a direct dependency

## MVP Deliverables

### Required files

- `Dockerfile`
- `docker-compose.yml`
- `entrypoint.sh`
- `.env.example`
- `scripts/fetch-upstream.sh`
- `scripts/verify.sh`
- `README.md`

### Required runtime behaviors

- build from pinned upstream source
- seed named volume into `/workspace`
- remap runtime UID/GID
- expose ttyd and viewer ports
- persist generated artifacts
- verify startup and basic HTTP/runtime health

## Suggested Operational Flow

### First-time startup

1. set env values
2. build image
3. start compose stack
4. run verification script

### Refresh to a new upstream version

1. update pinned upstream version
2. rebuild image
3. if workspace schema/content must refresh, recreate volume
4. rerun verification

## Risks

### 1. Upstream layout drift

If upstream reorganizes viewer, scripts, or package paths, this wrapper may need Dockerfile/entrypoint updates.

### 2. Named-volume refresh friction

Named-volume seeding improves isolation, but it makes source refresh more explicit.

### 3. Release gap

The deployment behavior proven in PR #114 may remain unavailable in official releases for some time.

## Risk Mitigations

- pin versions explicitly
- keep wrapper logic minimal
- verify against each upstream upgrade
- avoid forking upstream application logic unless absolutely necessary

## Recommendation Summary

Build this repository as a thin deployment wrapper around upstream releases.

Treat PR #114 as the architectural reference for:

- workspace volume strategy
- permission handling
- startup orchestration
- verification workflow

But do not assume official upstream releases already include that behavior.
