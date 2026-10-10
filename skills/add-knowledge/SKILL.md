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
7. Document paths passed to `kb-okf` write/edit/move tools are relative to the KB content dir (`knowledge/`, see `area_ok_config` key `content`). NEVER prefix them with `knowledge/` (wrong: `knowledge/projects/x`, right: `projects/x`). Search results and `exec` output show on-disk paths that include `knowledge/`; strip that prefix before writing. Do not copy the path of an existing doc under `knowledge/knowledge/...` — that is a misplaced doc, not a convention.
8. Before creating a doc, `exec ls` the target folder (e.g. `ls knowledge/projects/<project>`) to confirm sibling naming and location, and check the written path has no doubled `knowledge/`.

## Workflow

1. Search existing knowledge before creating a new document. Use tool `kb-okf__search` with following parameters: `cwd`, `limit` (set to 1), `query`.
2. If `resultCount` is 0, create a new document.
3. Otherwise, update the existing document.
   1. Get the document path from the search result: `results[0].path`.
