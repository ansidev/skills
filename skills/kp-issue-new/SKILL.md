---
name: kp-issue-new
description: Use this skill whenever the user wants to create a new issue in Kanpal. This includes requests to "file a bug", "create a issue", "log an issue", or any mention of tracking a new task or bug in Kanpal.
license: MIT
---

# Kanpal Issue Creation

This skill enables the creation of new issues in the Kanpal tracking system.

## Rules

1. MUST use available tools from `kanpal` MCP.
2. NEVER implement a issue in the main working tree. Implementation MUST happen in a separate git worktree, managed together with its herdr workspace. The worktree is created by skill `kp-issue-start`; this skill only delegates and must not create or reuse a worktree itself.
3. ONLY create issue, NEVER start implementation without user's confirmation.

## Inputs

1. Default inputs for the new issue:
  - status = "todo".
  - priority = "medium".

2. Required inputs

  - Project prefix

## Workflow

1. Read the user prompt and try to collect the project prefix. If you cannot get them, ask user.
2. Call tool `kanpal_get_project` with parameter `{"prefix": "<project-prefix>"}`, then get project ID from field `id`. If the project is not found, stop and inform user.
3. Evaluate the priority for the new issue.
4. NEVER create the new issue without the user's confirmation. DO NOT overconfidence. Once you collect all information, you MUST ask user for confirmation before creation.
5. Once the user confirms the information of the new issue, **create the issue** by using the `kanpal_create_issue` tool.
6. **Confirm and Report**: Once the tool returns a successful response, extract the resulting issue ID and report it clearly to the user. Example response: "The issue X has been created."
7. **Ask Before Implementation**: After reporting the issue ID, ask the user whether they want to start implementation. Do not start implementation automatically, and do not treat an unanswered or implicit response as confirmation.
8. **Handle the Decision**:
   - If the user explicitly confirms, invoke `/kp-issue-start <issue-prefix>` to begin implementation. `kb-issue-start` sets up the isolated worktree environment, so all implementation work happens there, never in the current working tree.
   - If the user declines, leave the issue in its created state and take no implementation action.
9. If issue creation fails, surface the failure and do not claim that a issue was created or begin implementation.
