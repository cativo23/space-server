# Architecture Decision Records

This folder tracks significant architectural decisions for the space-server stack — the *why* behind choices that aren't obvious from reading code.

Format: lightweight [Michael Nygard ADR](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions). Each file is `NNNN-kebab-title.md` and follows the [template](template.md).

## Status legend

| Status | Meaning |
|---|---|
| `proposed` | Drafted, not yet implemented |
| `accepted` | Decision made and shipping |
| `superseded by ADR-XXXX` | No longer current; see the new ADR |
| `deprecated` | The decision is reversed and no replacement was needed |

## Index

| # | Title | Status |
|---|---|---|
| [0001](0001-single-source-of-truth.md) | Repository as single source of truth for infrastructure | accepted |
| [0002](0002-observability-before-features.md) | Adopt observability before scaling features | accepted |
| [0003](0003-smtp-relay-via-resend.md) | Route outbound mail through Resend SMTP relay | accepted |
| [0004](0004-live-infra-signal-via-docker-socket-proxy.md) | Live container/stack counts via the docker-socket-proxy | accepted |

## Adding a new ADR

1. Copy [`template.md`](template.md) to `NNNN-short-title.md` where `NNNN` is the next sequence number
2. Set status to `proposed` while drafting; flip to `accepted` once shipped
3. Add a row to the index above
4. Reference the ADR by ID in commit messages affecting the decision
