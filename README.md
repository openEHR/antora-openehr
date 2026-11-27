# openEHR Specifications — Antora Migration Project

[![Antora](https://img.shields.io/badge/Antora-3.1-blue)]()

This repository provides the structure and tools to migrate the openEHR specifications to Antora and to build a unified, multi‑repository, multi‑version documentation site.

## Quick Start

To set up everything from scratch and launch a local preview, run:

```bash
make all
```

This will wipe any previous state, clone all repositories, create release branches, run the migration, build the site, and open a preview at http://localhost:8080.

Use this README for a high‑level overview. For setup and commands, start with `START-HERE.md`.

## What this project is

- A coherent Antora playbook and UI to publish the openEHR specifications
- A migration approach that reshapes each specification repo into Antora modules
- A set of helper scripts and validations to keep repos consistent
- A build layout that supports both local and containerized workflows

Why Antora:
- Supports multiple versions via Git branches
- Keeps components in separate repositories but builds one cohesive site
- Enables clean cross‑referencing across components and versions

## What’s in this repo

- `antora-playbook*.yml` — Antora configuration for production and local builds
- `src/supplemental-ui/` — UI assets (CSS, partials, shared images)
- `src/extensions/` — Antora extensions (e.g., `load-global-vars.js`)
- `scripts/` — migration and validation helpers
- `examples/` — before/after structure samples
- `repos/` — the place where specification repos are cloned for local builds
- `specs/` — components authored natively in Antora (ITS-FDR); a content source of the playbooks, never migrated. See `specs/ITS-FDR/README.md`; run its gates with `make check-fdr` after a build.

See `QUICK-REFERENCE.md` for a concise command cheat sheet and `MIGRATION-GUIDE.md` for details of the migration model and structure.

## Who should read what

- New contributors: start with `START-HERE.md` (installation and how to run)
- Editors/authors: see `MIGRATION-GUIDE.md` (how content is organized in Antora)
- Operators: see `QUICK-REFERENCE.md` (frequent commands)

## Directory Structure Overview

```
antora-openehr-migration/
├── 📄 Configuration
│   ├── antora-playbook.yml
│   ├── antora-playbook-local.yml
│   ├── package.json
│   ├── Dockerfile
│   └── docker-compose.yml
│
├── 🛠️ Build Tools
│   ├── Makefile (main automation)
│   └── scripts/
│       ├── migration/
│       │   ├── main-migrate-repo.sh
│       │   ├── _lib.sh
│       │   └── 1..13 + 3a/4a step scripts
│       ├── create-release-branches.sh
│       └── validate-structure.sh
│
├── 📘 Native Antora components (never migrated)
│   └── specs/ITS-FDR/            # Federation Tier with AQL; gates: make check-fdr
│
├── 🧩 Source
│   └── src/
│       ├── extensions/
│       │   └── load-global-vars.js
│       └── supplemental-ui/
│           ├── css/
│           ├── img/
│           └── partials/
│
├── 📚 Documentation
│   ├── README.md
│   ├── MIGRATION-GUIDE.md
│   ├── QUICK-REFERENCE.md
│   └── CHANGELOG.md
│
└── 💡 Examples
    ├── before/STRUCTURE.md
    └── after/STRUCTURE.md
```
---

## Links

- Start here: `START-HERE.md`
- Migration model: `MIGRATION-GUIDE.md`
- Commands cheat sheet: `QUICK-REFERENCE.md`
- Changelog: `CHANGELOG.md`
- Antora docs: https://docs.antora.org

—

Status: Active Development
