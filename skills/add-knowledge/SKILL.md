---
name: add-knowledge
description: Add knowledge to OpenKnowledge base. Use this skill to add new knowledge or update existing knowledge in the OpenKnowledge base.
license: MIT
---

# add-knowledge

## When to use

When the user asks to save, remember, document, or add knowledge to the second brain.

## Rules

1. You MUST use the MCP called `kb-okf`.
2. If tool calls require the working directory (usually `cwd` parameter), you MUST use the working directory from the respective MCP configuration key `cwd`. You may need to read MCP configurations from `~/.config/mcp/mcp.json`.

## Workflow

1. Search existing knowledge before creating a new document.
2. Prefer updating an existing document when the knowledge already belongs there.
3. Create a new document only when appropriate.
4. Preserve the existing OpenKnowledge structure and conventions.
5. Add links to related knowledge when useful.
6. Do not create knowledge inside the current coding project unless explicitly requested.
7. After writing, verify the result.
