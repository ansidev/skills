---
name: tb-issue-start
description: Use this skill to start working on the solution for the relevant taskboard issue. When the user asks to fix, correct, or start an issue in the taskboard, this skill will be activated.
---

# tb-issue-start

## When to use

Use this skill when the user asks to fix, correct, or resolve an issue in the taskboard. This skill will be activated to start working on the solution for the relevant taskboard issue.

## Rules

1. Use the MCP tools of the MCP called `taskboard`.
2. Use skill `tb-cli` to fetch information not available via MCP.

## Input

1. Input is the taskboard ticket ID or ticket prefix.
2. If the input length is 26, it is considered a ticket ID. If the input length is shorter than 26, it is considered a ticket prefix.

## Instructions

1. If user given a ticket prefix, run command `taskboard ticket list | grep <prefix>` to get the ticket ID. You should not ask user for the ticket ID if the user has already provided a ticket prefix.
2. Use tool `taskboard_get_ticket` to retrieve the ticket details with id is the given/resolved ticket ID. If the ticket is not found, return a message indicating that the ticket does not exist.
3. If the ticket status is todo, use tool `taskboard_update_ticket` to change the status to in_progress and team to agent. Otherwise, if the ticket status is in_progress, continue to the next step. If the ticket status is done, return a message indicating that the issue has already been resolved.
4. Use skill `spec-driven-development` to create a solution for the issue.
5. Important rule: The output of phase 1 of the `spec-driven-development` skill (`Requirements Gathering`) MUST be updated back to the taskboard ticket description.
6. Additional steps as needed by the `spec-driven-development` skill to complete the solution.
