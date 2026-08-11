---
name: markdown
description: Conventions for writing and formatting markdown documents
---

## What This Skill Does

This skill defines conventions for writing markdown files that are easy to read in source, produce clean diffs in version control, and render correctly.
Load this skill when creating or substantially editing markdown documents.

## Line Breaking

Use **semantic line breaks** (one sentence per line).
Break lines at sentence boundaries, not at a fixed column width.

This produces git diffs that show exactly which sentence changed, rather than reflowing entire paragraphs.

**Do:**
```markdown
This is the first sentence.
This is the second sentence, which is somewhat longer.
Here is a third.
```

**Don't:**
```markdown
This is the first sentence. This is the second
sentence, which is somewhat longer. Here is a
third.
```

Exceptions where line breaks should NOT split at sentence boundaries:
- **List items** — short items stay on one line; long items may wrap with indentation for continuation lines
- **Table cells** — content stays on one line per cell (tables cannot have mid-cell line breaks)
- **Code blocks** — use the language's own conventions
- **Headings** — always a single line

## Headings

Use ATX-style headings (`#`, `##`, etc.), not underline-style (`===`, `---`).
Leave one blank line before and after headings.
Do not skip heading levels (e.g., don't jump from `##` to `####`).

## Lists

Use `-` for unordered lists (not `*` or `+`).
Use `1.` for ordered lists only when order matters.
Indent nested lists by 2 spaces.

## Links and References

Prefer inline links `[text](url)` for short URLs.
For URLs that appear multiple times or are very long, use reference-style links:
```markdown
See the [documentation][docs] for details.

[docs]: https://example.com/very/long/path/to/documentation
```

## Emphasis

Use `**bold**` for strong emphasis and `*italic*` for regular emphasis.
Do not use underscores (`__bold__`, `_italic_`) — they are ambiguous with filenames and identifiers.

## Code

Use backticks for inline code: `` `variable_name` ``.
Use fenced code blocks with a language identifier for multi-line code.
Always include a language hint after the opening triple backticks when the content has a recognizable language or format (e.g., `python`, `bash`, `json`, `yaml`, `markdown`, `lua`, `vim`).
For plain text or mixed-format content with no applicable language, leave the hint blank.

````markdown
```python
def example():
    pass
```
````

## Tables

Include a header row and separator row.
Align separator dashes to the left (default) unless right/center alignment is meaningful.
Keep table content concise — if a cell needs multiple sentences, consider restructuring as a list or subsection instead.

## Whitespace

- One blank line between block elements (paragraphs, lists, code blocks, headings).
- No trailing whitespace on any line.
- Files end with a single newline (no trailing blank lines).
- Use LF line endings, not CRLF.
