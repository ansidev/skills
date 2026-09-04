## Review Output Format

Use this structure:

```markdown
## Review result

### Fixed/Ignored Issues

Format: Table

Columns
- No.
- Issue Description
- Issue Rank
- Status (e.g. FIXED, PARTIALLY FIXED, IGNORED)
- How was it fixed?

If the table has no data (e.g. first run), DO NOT output this section.

### Non-fixed Issues (Old and New)

### Issue 1 - <Issue Rank> - <Old|New>
- Summary:
- File Location:
- Why this is an issue:
- Impact:

### Issue 2 (if any) - <Issue Rank> - <Old|New>
- Summary:
- File Location:
- Why this is an issue:
- Impact:

## Proposed Fixes
- Fix 1:
  - Fix issue <Issue Number>
  - Actions:
  - Why it addresses the issue:
  - Validation steps:
- Fix 2:
  - Fix issue <Issue Number>
  - Actions:
  - Why it addresses the issue:
  - Validation steps:

## Unknowns / Follow-ups
- Questions or everything else
```

## Rules

IMPORTANT: This section MUST NOT be included in the output

1. If an issue is marked as IGNORED by the user but then it is fixed by the PR assignee, then the issue should be treated as fixed issue, status should not be IGNORED but FIXED.
2. If an issue is marked as PARTIALLY FIXED then Non-fix Issues should list the linked non-fixed issue.
