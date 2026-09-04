---
name: ad-review-pr
description: Use when reviewing a pull request for correctness, completeness, and quality.
---

# ad-review-pr

## Rules

1. You MUST NOT modify code.
2. You MUST verify git hosting provider.
3. You MUST verify the branch name and commit history.
4. You can use skill `gh-axi` if the git hosting provider is GitHub, otherwise use `git` only.

## Workflow

1. Pull changes from the remote branch, if you cannot pull due to unstaged changes, stash changes and retry.
2. Spawn a subagent agent review the pull request.
3. Summary final review findings.

## Response

The response MUST indicates:
1. What is the issue ranking? (e.g. High, Medium, Low,...)
2. What is the issue?
3. Where is the located file path, begin and end line numbers?
4. Why is that an issue?
5. How does user should fix it? The complexity ranking of the solution (e.g. easy, hard,...)

## Output format

Read `skills/ad-review-output-format.md`.
