---
name: tb-project-new
description: Use this skill whenever the user wants to create a new project in Taskboard.
license: MIT
---

# Taskboard Project Creation

This skill enables the creation of new projects in the Taskboard tracking system.

## Rules

1. Use available tools from `taskboard` MCP server.

## Inputs

1. Required inputs for the new project:
  - name.
  - prefix.
2. Optional inputs for the new project:
  - color: use random color for the new project if the user does not provide a color. The color format should be a hex color code (e.g., #FF5733).
  - icon: use a random emoji for the new project if the user does not provide an emoji. The emoji should be a single character (e.g., 🚀, 🎨, 🛠️).

## Workflow

1. Ask the user for a clear and concise required inputs of the project they want to create.
2. Once the user provides the necessary information, **create the project** by using the `taskboard_create_project` tool.
3. **Confirm and Report**: Once the tool returns a successful response, extract the resulting project information: name, id, prefix and report it clearly to the user. Example response: "The project `project-1` has been created with ID `PROJECT1` and prefix `PJT-1`".
