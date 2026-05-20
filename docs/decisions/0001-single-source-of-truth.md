# ADR-0001: Repository as single source of truth for infrastructure

## Status

accepted (2026-05-14)

## Context

The production host (`polaris2`) was set up by SCP-ing files during the laptop → VPS migration. As a result, the host had a working copy of stack files but no version control. Application stacks (Ghost, portfolio, portfolio-api, hello-kitty-landing) lived in sibling repositories committed elsewhere, and the running `~/space-server/` directory contained whatever happened to be on disk that day. Reproducibility was theoretical: there was no single artifact that, given a fresh VPS, could recreate the current production state.

The Ansible-based reproducibility goal stated in the original roadmap is blocked until there is one place to read the truth from.

## Decision

This repository is the canonical source of truth for everything running on `polaris2`. The production directory is a git working copy tracking `origin/main`; deploys are `git pull && docker compose up -d`. Application stacks that currently live in sibling repos will be integrated via Compose's [`include:`](https://docs.docker.com/compose/multiple-compose-files/include/) directive (Compose v2.20+) once those stacks expose a stable compose file at their repo root.

Secrets stay out of the repo: `.env`, `traefik/dynamic/auth.yml`, mail account files, and TLS certificates are gitignored and live only on the production host. `.example` templates document the expected shape of each.

## Alternatives considered

- **Git submodules** — Tighter coupling but adds a workflow tax (`git submodule update --remote`) every change. Rejected for the friction it adds to a single-maintainer project.
- **Consolidate all application repos into this one** — Simple but loses the natural boundary between infra and app history. Rejected because Ghost/portfolio repos have their own release cadence and CI.
- **Pulumi / Terraform** — Overkill for a single-node Docker Compose deploy. Reconsider if multi-node ever happens.

## Consequences

### Positive

- A fresh VPS can be brought to current production state by cloning this repo + populating gitignored secrets.
- Every config change is reviewable via PR; CI (`.github/workflows/validate.yml`) catches syntax breakage before merge.
- The improvement roadmap ([`IMPROVEMENT-PLAN.md`](../../IMPROVEMENT-PLAN.md)) lives next to the code it talks about.

### Negative

- Application stacks not yet integrated via `include:` still require manual coordination between repos.
- The git history on `polaris2` started fresh on 2026-05-14; pre-existing local edits had to be reconciled with `git reset --mixed origin/main` followed by `git checkout -- .` for safe files.

### Follow-ups

- ADR for Compose `include:` adoption once Ghost/portfolio repos expose `compose.yml` at their roots.
- Renovate or Watchtower for managed image-version bumps (see ADR-0002 follow-ups).
