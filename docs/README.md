# Docs

Everything published about this platform lives here. **This directory is the
single source of truth**, GitHub Pages serves it directly, so anything published
is generated from the same files that are reviewed in pull requests and can never
drift out of step with the platform it describes.

Site: <https://samueltillman.github.io/aws-eks-reference-platform/>

## The Published Site

| Page | Audience | Purpose |
|---|---|---|
| [architecture.html](architecture.html) | engineers | the full visual reference: layer map, credential flow, audit trail, networking, EKS internals |
| [value-map.html](value-map.html) | managers | what it costs and what risk each capability retires |
| [account-landscape.html](account-landscape.html) | managers | the five accounts and which services run in each |
| [roadmap.html](roadmap.html) | managers | layer status and what each layer unlocks |

`index.html` redirects to `architecture.html`.

> **Single source of truth, deliberately.** These pages were briefly duplicated as
> standalone hosted artifacts, which immediately drifted: a corrected cost split
> landed in the repo while the shared copy still showed the old figures. The copies
> are now thin pointer pages that link here, so previously shared links still work
> but there is only one place the content actually lives. If you publish a copy
> anywhere else, make it a pointer, not a fork.

## Written Documentation

| Doc | What it is |
|---|---|
| [getting-started.md](getting-started.md) | fork to running platform, step by step, with costs, verification and teardown |
| [bootstrap.md](bootstrap.md) | the manual, one-time steps that cannot be Terraformed |
| [teardown-rebuild.md](teardown-rebuild.md) | destroying and rebuilding from the button |
| [control-tower-comparison.md](control-tower-comparison.md) | what AWS Control Tower would have done for you, step by step |
| [adr/](adr/) | every significant decision, numbered and never renumbered |

## Issue Logs

Real failures hit while building this, with the actual error text, root cause, fix
and prevention. Check the log for your layer **before** debugging from scratch.

- [layer0-issues.md](layer0-issues.md), bootstrap and organization
- [layer1-issues.md](layer1-issues.md), landing zone (the most common snags)
- [layer2-issues.md](layer2-issues.md), cluster, CI/CD and GitOps

Entries are kept honest, including the ones that are still unresolved and the ones
where an early diagnosis turned out to be wrong. The wrong turns are usually the
useful part.
