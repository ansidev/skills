---
name: ad-investigate
description: Use when investigating an issue
---

# Issue Investigation

## Overview

Structured analysis of the issue to isolate root causes with evidence before proposing fixes.

## When to Use

- User provides a log file path or pasted the input.
- User asks for root cause from stack traces or incident logs.
- User wants explained causes plus concrete remediation options.

## Inputs

Required:
- A log file path or pasted input

Optional:
- Time window where failure occurred
- Environment (`dev`, `staging`, `prod`)
- Recent changes or deployment info

## Workflow

**REQUIRED SUB-SKILL:** Read and follow `superpowers:systematic-debugging` before proposing any fix.

1. Read the full log first, then isolate the earliest high-signal errors.
2. Build an evidence table (timestamp, component, message, probable subsystem).
3. Group related errors to distinguish primary failures from cascade noise.
4. State root-cause hypotheses with direct log evidence.
5. Validate each hypothesis against sequence, context, and known behavior.
6. Report confirmed root causes, explain impact, then propose minimal fixes.

## Output format

Use this structure:

```markdown
## Root Cause Analysis

### Root Cause 1
- Evidence:
- Why this is the root cause:
- Impact:

### Root Cause 2 (if any)
- Evidence:
- Why this is the root cause:
- Impact:

## Proposed Fixes
- Fix 1:
  - Why it addresses the root cause:
  - Validation steps:
- Fix 2:
  - Why it addresses the root cause:
  - Validation steps:

## Unknowns / Follow-ups
- Missing evidence:
- Additional logs or metrics needed:
```

## Guardrails

- Do not propose fixes without identifying root cause evidence first.
- Treat repeated downstream exceptions as potential symptoms until proven otherwise.
- Prefer smallest safe fix that removes the source failure.
- If evidence is insufficient, explicitly say what is missing and request it.
- Redact or mask secrets, tokens, credentials, and PII when quoting logs.

## Common Mistakes

- Jumping straight to fixes without isolating first-cause errors.
- Treating every repeated error as a separate root cause.
- Ignoring chronology and missing the first triggering event.
- Presenting assumptions without quoting supporting log evidence.
