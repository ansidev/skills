---
name: kp-issue-new
description: Use this skill whenever the user wants to create a new issue in Kanpal. This includes requests to "file a bug", "create a issue", "log an issue", or any mention of tracking a new task or bug in Kanpal.
license: MIT
---

# Kanpal Issue Creation

This skill enables the creation of new issues in the Kanpal tracking system.

## Rules

1. MUST use available tools from `kanpal` MCP.
2. Respond to the user in English only, regardless of the language the user writes in.
2. NEVER implement a issue in the main working tree. Implementation MUST happen in a separate git worktree. The worktree is created by skill `kp-issue-start`; host lifecycle work is selected through the vendored host-runtime adapter at `<skill-directory>/lib/host-runtime`, which reports `herdr-tui`, `herdr-desktop`, `outside`, or `unknown`. An `unknown` runtime is a stop condition; it must never trigger a fallback host command.
3. ONLY create issue, NEVER start implementation without user's confirmation.

## Inputs

1. Default inputs for the new issue:
  - status = "todo".

2. Required inputs

  - Project prefix

## Workflow

1. Read the user prompt.
2. Use skill `task-breakdown` to split requirements into smaller issues, and evaluate the priority for each issue and their dependencies.
3. Try to extract the project prefix from the user prompt. If you cannot get them, ask user.
4. Call tool `kanpal_get_project` with parameter `{"prefix": "<project-prefix>"}`, then get project ID from field `id`. If the project is not found, stop and inform user.
5. Build the complete issue draft from the collected information: title, description, priority, and dependencies. Before requesting confirmation, you MUST render/print the full draft to the user so the content can be reviewed accurately. Do not ask for confirmation without showing the draft.
6. Request confirmation using the `ask_user_question` tool. The question must include the draft content and offer options: "Confirm" to create the issue as drafted, "Revise draft" to let the user adjust the draft, and "Cancel" to abort. Handle the choice:
   - If "Confirm": proceed to create the issue.
   - If "Revise draft": update the draft per the user's feedback, re-render it, and ask again.
   - If "Cancel": stop and take no creation action.
7. NEVER create the new issue without the user's confirmation obtained through `ask_user_question` as above. Once you collect all information, you MUST ask user for confirmation before creation.
8. Once the user confirms the information of the new issue:
   1. **Create the issue** by using the `kanpal_create_issue` tool.
   2. **Set issue dependencies** by using the `kanpal_add_dependency` tool.
9. **Confirm and Report**: Once the tool returns a successful response, extract the resulting issue ID and report it clearly to the user. Example response: "The issue X has been created."
10. **Ask Before Implementation**: After reporting the issue ID, ask the user whether they want to start implementation using the `ask_user_question` tool. The question must offer options such as "Start implementation" to begin the work and "Not now" to leave the issue as created. Do not start implementation automatically, and do not treat an unanswered or implicit response as confirmation.
11.  **Handle the Decision**:
 - If the user explicitly confirms, invoke skill `kp-issue-start <issue-key>` (the skill sets up the isolated worktree environment through the host-runtime adapter, so all implementation work happens in the worktree, never in the current working tree). Do not call host commands from this skill.
   - If the user declines, leave the issue in its created state and take no implementation action.
12. If issue creation fails, surface the failure and do not claim that a issue was created or begin implementation.
