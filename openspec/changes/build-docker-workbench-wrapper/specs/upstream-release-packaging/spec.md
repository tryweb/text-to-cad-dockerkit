## ADDED Requirements

### Requirement: Build image from pinned upstream release tag
The system SHALL build the workbench image from a pinned upstream `earthtojake/text-to-cad` release tag fetched during Docker image build rather than from an upstream branch checkout or a maintained fork.

#### Scenario: Build uses an explicit upstream version
- **WHEN** an operator sets `TEXT_TO_CAD_VERSION` for the build flow
- **THEN** the image build SHALL resolve upstream source from that release tag

#### Scenario: Build does not depend on unreleased branch behavior
- **WHEN** the selected upstream release does not include PR #114
- **THEN** the wrapper repository SHALL still provide its own deployment-layer behavior without requiring an upstream feature branch

### Requirement: Packaging ownership stays in the wrapper repository
The system SHALL keep Docker packaging, runtime bootstrap, and deployment workflow files in `text-to-cad-dockerkit` rather than modifying upstream application source.

#### Scenario: Wrapper files are locally owned
- **WHEN** implementation files such as `Dockerfile`, `docker-compose.yml`, or `entrypoint.sh` are created or changed
- **THEN** those files SHALL live in this repository and SHALL NOT require committing changes into the upstream repository
