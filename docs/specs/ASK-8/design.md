# Design: complete `kp-issue-finish` closeout verification

## Overview

Make closeout an explicit checklist with observable results. Terminal status becomes a verification-only route: it cannot merge or change status, but it does re-check the checklist and reports any incomplete item. The normal merge route uses the same checklist and does not declare completion until the final runtime-cleanup check has evidence.

## Architecture

`skills/kp-issue-finish/SKILL.md` remains the workflow authority. The vendored `lib/host-runtime` remains the only host integration boundary. Tests in `tests/test_issue_skills.py` validate that the skill contract includes the required paths and safety checks.

## Components and interfaces

| Component | Change |
| --- | --- |
| Terminal-status preflight | Enumerate checklist items; verify rather than early-return. |
| Git preflight | Compare untracked paths against operation write paths; preserve unrelated files. |
| Host finalizer | Run adapter lookup/close/lookup, record cleanup evidence or N/A, and scope by issue key. |
| Completion report | Emit one result per required checklist item; incomplete evidence is never presented as success. |

## Decision

Use prescriptive workflow sections plus static regression assertions rather than introducing a new executable orchestrator. The behavior is agent-driven, so the skill needs enforceable structure; the adapter already owns runtime operations and does not need a new API.

## Error handling

- An unknown adapter runtime stops the host path.
- A conflicting untracked path stops before mutation and names the path.
- Failed cleanup or absence verification is reported as incomplete, not silently accepted.
- `outside` records host cleanup as N/A.

## Testing strategy

Add behavior tests asserting terminal-status verification, per-item evidence, runtime close-and-verify sequencing, and both untracked-file outcomes. Run the targeted suite and the entire Python test suite.
