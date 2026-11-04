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
2. MUST pass `"cwd": "/Users/ansidev/projects/kb"` explicitly on EVERY `kb-okf` tool call (`ok_skills`, `ok_exec`, `search`, write/edit/move, etc.). No exceptions, even if the call seems not to need it.
   - NEVER rely on the current working directory or the MCP client root; they may point at another project (e.g. `/Users/ansidev/projects/personal/kanpal/knowledge`).
   - `ok_exec` commands run relative to `cwd`, and `cwd` must be inside an OpenKnowledge project (contain `.ok/config.yml`).
3. MUST preserve the existing OpenKnowledge structure and conventions.
4. DO NOT create knowledge inside the current coding project unless explicitly requested.
5. Add links to related knowledge when useful.
6. After writing, verify the result.
7. Document paths passed to `kb-okf` write/edit/move tools are relative to the KB content dir (`knowledge/`, see `area_ok_config` key `content`). NEVER prefix them with `knowledge/` (wrong: `knowledge/projects/x`, right: `projects/x`). Search results and `exec` output show on-disk paths that include `knowledge/`; strip that prefix before writing. Do not copy the path of an existing doc under `knowledge/knowledge/...` — that is a misplaced doc, not a convention.
8. Resolve the KB project slug from the current coding repository/name (`agent-skills`), not from an issue prefix/tracker project. If an issue key maps to a tracker project different from the repository, still use the repository slug for KB paths. First run `exec ls knowledge/projects` and choose the existing slug matching the repository basename. If no slug matches, ask the user for the KB project slug before writing.
9. Before creating a doc, `exec ls` the target folder (e.g. `ls knowledge/projects/<project>`) to confirm sibling naming and location, and check the written path has no doubled `knowledge/`.

## Workflow

1. Search existing knowledge before creating a new document. Use tool `kb-okf__search` with following parameters: `cwd` (always `/Users/ansidev/projects/kb`), `limit` (set to 1), `query`.

   ```json
   {"cwd": "/Users/ansidev/projects/kb", "limit": 1, "query": "<topic>"}
   ```
2. If `resultCount` is 0, create a new document.
3. Otherwise, update the existing document.
   1. Get the document path from the search result: `results[0].path`.

## Examples (every call includes `cwd`)

```json
// ok_skills
{"cwd": "/Users/ansidev/projects/kb"}

// ok_exec
{"cwd": "/Users/ansidev/projects/kb", "command": "ls knowledge/projects/<project>"}
```

## Troubleshooting

Both errors below mean `cwd` was omitted or wrong. Retry the same call with `"cwd": "/Users/ansidev/projects/kb"`.

- `Error: cwd is required for tool calls against the global MCP server...` (e.g. `ok_skills`): `cwd` was not passed. Add it.
- `exec failed: No OpenKnowledge project found at or above <path>...` (e.g. `ok_exec`): `cwd` was missing and a different working directory was inherited, or points outside an OK project. Set `cwd` to `/Users/ansidev/projects/kb`, which contains `.ok/config.yml`.
