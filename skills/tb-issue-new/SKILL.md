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

## Inputs

1. Default inputs for the new issue:
  - status = "todo".
  - priority = "medium".

## Workflow

1. Ask the user for a clear and concise required inputs of the issue they want to create.
2. Once the user provides the necessary information, **create the ticket** by using the `taskboard_create_ticket` tool.
3. **Confirm and Report**: Once the tool returns a successful response, extract the resulting ticket ID (e.g., "ISSUE-12345") and report it clearly to the user. Example response: "The issue ISSUE-12345 has been created"
