# ITS-FDR: Federation Tier with AQL

This directory is the Antora content source for the openEHR component **ITS-FDR**,
the *Federation Tier with AQL* specification. It sits in the ITS zone next to ITS-REST.

> **Do not run the migration scripts on this directory.** The specification is
> authored natively in Antora. `scripts/migration/` would delete `modules/` and
> rewrite the content (class xrefs, `<<…>>` references, listing styles, index pages).
> No migration step or Makefile repo loop reads `specs/`.

## Provenance

| | |
|---|---|
| Source repository | `syntaric/openehr-federation-spec` |
| Source commit | `b40a29a` |
| Release | **1.0.0**, approved by the openEHR SEC on 2026-10-12. The content of `b40a29a` is published here as the first openEHR release, 1.0.0. |
| Copied with | `git archive b40a29a \| tar -x` (committed content only) |

The specification is copied **byte for byte**, except for the release-number changes
listed below. Those are the only edits to specification text:

| Path | Status |
|---|---|
| `Release-1.0.0/modules/federation_aql/**` | Copy of the source `modules/ROOT/**` (moved to a named module; every xref and image in it is module-relative). Verbatim except for the three release-number edits below. |
| `…/pages/index.adoc` | Editorial note: says the spec "is published as release 1.0.0"; the history of earlier source releases is removed |
| `…/pages/rest-facade.adoc` (§7a.2) | `federation.spec_version`: a 1.0.0 gateway reports `"1.0"`; the sentence on the move from `"1.0"` is removed; the example body says `"1.0"` |
| `…/attachments/federated-result-set.schema.json` | `row_endpoints` description: "Federation addition", without a since-release |
| `Release-1.0.0/diagrams/*.puml` | Verbatim (the image captions cite `diagrams/<file>.puml`) |
| `LICENSE` | Verbatim (CC0 1.0) |
| `tools/traceability.tsv`, `tools/traceability-exceptions.txt` | Verbatim |
| `Release-1.0.0/antora.yml` | Adapted from the source descriptor: `name: ITS-FDR`, `version: Release-1.0.0`, `spec-version: '1.0.0'`, `start_page: ROOT:index.adoc`, two nav files. `title`, `spec-status` and `spec-date` are verbatim. |
| `Release-1.0.0/modules/ROOT/**` | New: the openEHR component landing page (status badge, release, the first sentence of §1 Summary verbatim, link to the specification) |
| `tools/*.sh` | Vendored gates with tooling-only changes: env overrides `SPEC_PAGES`, `SPEC_SCHEMAS`, `AJV` (defaults unchanged), and `check-anchors.sh` resolves directory hrefs to `index.html` (the site uses `html_extension_style: indexify`) |

Not copied from the source repository: `node_modules`, `build`, `package*.json`,
`Makefile`, `antora-playbook.yml`, `.github`, `README.md` and `CONTRIBUTING.md`.
Read the last two in the source repository.

## Layout

```
specs/ITS-FDR/
├── README.md            # this file
├── LICENSE              # CC0, verbatim
├── tools/               # vendored CI gates
└── Release-1.0.0/       # one directory per published release
    ├── antora.yml
    ├── diagrams/*.puml
    └── modules/
        ├── ROOT/        # landing page
        └── federation_aql/
```

All three playbooks register it as:

```yaml
- url: .
  branches: HEAD
  start_paths: specs/ITS-FDR/Release-*
```

Each `Release-*/antora.yml` supplies its own version. A new release is a new
sibling directory (`Release-<x.y.z>/`), next to the existing one.

## Gates

```bash
make build-local   # failure_level: warn, so a broken xref fails the build
make check-fdr     # prose § refs, traceability --assert, in-page anchors, JSON examples vs schemas
```

`make check-fdr` runs `tools/*.sh` against `Release-1.0.0` and `build/ITS-FDR/Release-1.0.0`.
Use `BUILD_DIR=<dir>` for another output directory. The traceability report goes to
`build/its-fdr-traceability.tsv`, so the vendored `tools/traceability.tsv` is not rewritten.

## Editing

Edit here. The specification text should change only through the spec's editors and
the SEC. Where it differs from openEHR conventions (licence, status wording, amendment
record, numbered headings, references, cross-spec xrefs), the difference is deliberate
until the SEC decides.
