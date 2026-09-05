---
name: tb-issue-new
description: Use this skill whenever the user wants to create a new issue in Taskboard. This includes requests to "file a bug", "create a ticket", "log an issue", or any mention of tracking a new task or bug in Taskboard.
license: MIT
---

# Taskboard Issue Creation

This skill enables the creation of new issues in the Taskboard tracking system.

## Rules

1. Use available tools from `taskboard` MCP server.
2. Use skill `tb-cli` to fetch information not available via MCP.
3. Never implement a ticket in the main working tree. Implementation MUST happen in a separate git worktree, managed together with its herdr workspace (see `tb-issue-finish/scripts/herdr-workspace.sh` for the `ws-new`, `wt-dir`, and `wt-delete` helpers). The worktree is created by skill `tb-issue-start`; this skill only delegates and must not create or reuse a worktree itself.

## Inputs

1. Default inputs for the new issue:
  - status = "todo".
  - priority = "medium".

## Workflow

1. Ask the user for a clear and concise required inputs of the issue they want to create.
2. Once the user provides the necessary information, **create the ticket** by using the `taskboard_create_ticket` tool.
3. **Confirm and Report**: Once the tool returns a successful response, extract the resulting ticket ID (e.g., "ISSUE-12345") and report it clearly to the user. Example response: "The issue ISSUE-12345 has been created."
4. **Ask Before Implementation**: After reporting the ticket ID, ask the user whether they want to start implementation. Do not start implementation automatically, and do not treat an unanswered or implicit response as confirmation.
5. **Handle the Decision**:
   - If the user explicitly confirms, invoke `/tb-issue-start <ticket-id>` to begin implementation. `tb-issue-start` sets up the isolated worktree environment, so all implementation work happens there, never in the current working tree.
   - If the user declines, leave the ticket in its created state and take no implementation action.
6. If ticket creation fails, surface the failure and do not claim that a ticket was created or begin implementation.
