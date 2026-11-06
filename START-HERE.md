# START HERE — Install and run the openEHR Antora toolchain

This is the canonical setup guide. It provides two paths:
- Native (Node.js) installation and commands
- Docker-based workflow (no local Node required)

For background about the migration model and Antora structure, see `MIGRATION-GUIDE.md`.

—

## Prerequisites

Choose ONE of the following:

- Native path:
  - Node.js 18 LTS (16+ supported, 18 recommended)
  - npm (ships with Node)
  - Git 2.0+
  - Make
  - Bash (for scripts)

- Docker path:
  - Docker and Docker Compose

Windows users: WSL2 is recommended for the native path.

—

### Steps to follow

1) Clone this repository (recursive recommended if submodules are used):
```bash
git clone --recursive <repo-url>
cd antora-openehr
```

2) If you choose to work with Docker instead, then start it now:
```bash
docker compose up -d --build
docker compose exec antora bash
```
The next steps can be run inside the docker container.

3) Install necessary npm packages and clone all specification repositories locally:
```bash
make install
```

4) Create release branches from tags and a `development` branch from `master` (used by Antora for the prerelease site):
```bash
make create-all-branches
```

5) Migrate one repository (try BASE first), then validate:
```bash
make migrate-repo REPO=specifications-BASE
make validate-structure REPO=specifications-BASE
```

Notes:
- Migration runs on the `development` branch of the target spec repo by default. Override with `MIGRATION_BRANCH=<branch>` if needed; the script will refuse to run if the branch doesn't exist locally (run step 4 first).
- The migration creates ~3 git checkpoint commits in the spec repo. Set `AUTO_COMMIT_CHECKPOINTS=0` to disable.
- UML class partials are regenerated via the Docker image `ghcr.io/openehr/bmm-publisher:0.13.0` (override with `BMM_PUBLISHER_IMAGE`). Local BMM JSON overlays can be supplied via `BMM_RESOURCES_OVERLAY=/path/to/dir` or by placing files under `<repo>/computable/BMM/*.bmm.json`.

To run class generation by itself (without a full migration):
```bash
make generate-uml-classes-repo REPO=specifications-BASE
```

6) Build and preview locally:
```bash
make build-local
make preview    # opens http://localhost:8080
```

7) Migrate remaining repositories and rebuild as needed:
```bash
make migrate-all
make validate-all
make build-local
```

8) If you used docker then stop services when done:
```bash
docker compose down
```

—

## Typical Workflow (both paths)

```bash
make install
make create-all-branches
make migrate-repo REPO=specifications-BASE
make validate-structure REPO=specifications-BASE
# Manual content updates: see MIGRATION-GUIDE.md (includes, images, xrefs)
make build-local && make preview
make migrate-all && make validate-all
```

—

## Troubleshooting (quick)

- Command not found → ensure you’re in the project root and have `make` installed
- npm install fails → verify Node.js version (use 18 LTS if possible)
- "antora.yml not found" → run a migration for that repository first
- Images or includes broken → follow the adjustments in `MIGRATION-GUIDE.md`
- UML class generation fails → verify Docker can pull `ghcr.io/openehr/bmm-publisher:0.13.0` and re-run migration

More details: see Troubleshooting sections in `MIGRATION-GUIDE.md` and `QUICK-REFERENCE.md`.

—

## Useful files

- `README.md` — high-level overview of the project (no commands)
- `MIGRATION-GUIDE.md` — migration structure and manual adjustments
- `QUICK-REFERENCE.md` — command cheat sheet
- `CHANGELOG.md` — changes over time


