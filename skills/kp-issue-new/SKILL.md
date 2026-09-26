---
name: kp-issue-new
description: Use this skill whenever the user wants to create a new issue in Kanpal. This includes requests to "file a bug", "create a ticket", "log an issue", or any mention of tracking a new task or bug in Kanpal.
license: MIT
---

# Kanpal Issue Creation

This skill enables the creation of new issues in the Kanpal tracking system.

## Rules

1. MUST use available tools from `kanpal` MCP.
2. NEVER implement a ticket in the main working tree. Implementation MUST happen in a separate git worktree, managed together with its herdr workspace. The worktree is created by skill `kp-issue-start`; this skill only delegates and must not create or reuse a worktree itself.
3. ONLY create ticket, NEVER start implementation without user's confirmation.

## Inputs

1. Default inputs for the new issue:
  - status = "todo".
  - priority = "medium".

2. Required inputs

  - Project prefix

## Workflow

1. Read the user prompt and try to collect the project prefix. If you cannot get them, ask user.
2. Call tool `kanpal_get_project` with parameter `{"prefix": "<project-prefix>"}`, then get project ID from field `id`. If the project is not found, stop and inform user.
3. NEVER create the new ticket without the user's confirmation. DO NOT overconfidence. Once you collect all information, you MUST ask user for confirmation before creation.
4. Once the user confirms the information of the new ticket, **create the ticket** by using the `kanpal_create_ticket` tool.
5. **Confirm and Report**: Once the tool returns a successful response, extract the resulting ticket ID and report it clearly to the user. Example response: "The issue X has been created."
6. **Ask Before Implementation**: After reporting the ticket ID, ask the user whether they want to start implementation. Do not start implementation automatically, and do not treat an unanswered or implicit response as confirmation.
7. **Handle the Decision**:
   - If the user explicitly confirms, invoke `/kp-issue-start <ticket-prefix>` to begin implementation. `kb-issue-start` sets up the isolated worktree environment, so all implementation work happens there, never in the current working tree.
   - If the user declines, leave the ticket in its created state and take no implementation action.
8. If ticket creation fails, surface the failure and do not claim that a ticket was created or begin implementation.
