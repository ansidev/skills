---
name: ad-research
description: Use when research something and save the result to the knowledgebase
license: MIT
---

# ad-research

## Overview

Use this skill when you need to research a topic and save the findings to the knowledgebase.

## When to Use

- User asks to research a topic or question
- User wants research findings documented in the knowledgebase
- User needs information gathered and saved for future reference

## Workflow

**REQUIRED SUB-SKILLS:**

1. Use skill `researcher` to conduct research based on the user inputs.
2. Use skill `add-knowledge` to save the research results to the knowledgebase.

## Inputs

Required:
- The research topic, question, or query

Optional:
- Specific scope or boundaries for the research
- Preferred sources or domains
- Output format preferences

## Output

A summary of the research findings with links or references to where the knowledge was saved in the knowledgebase.