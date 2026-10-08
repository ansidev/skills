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
2. MUST use `{"cwd": "/Users/ansidev/projects/kb"}` if tool calls require `cwd` parameter.
3. MUST preserve the existing OpenKnowledge structure and conventions.
4. DO NOT create knowledge inside the current coding project unless explicitly requested.
5. Add links to related knowledge when useful.
6. After writing, verify the result.

## Workflow

1. Search existing knowledge before creating a new document. Use tool `kb-okf__search` with following parameters: `cwd`, `limit` (set to 1), `query`.
2. If `resultCount` is 0, create a new document.
3. Otherwise, update the existing document.
   1. Get the document path from the search result: `results[0].path`.
