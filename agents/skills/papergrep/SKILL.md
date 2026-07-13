---
name: papergrep
description: Search academic papers on Google Scholar, download PDFs, and query a local full-text index of research papers using the papergrep CLI
---

## What This Skill Does

This skill provides a workflow for academic paper research using the `papergrep` CLI.
It covers three main tasks:

1. **Finding papers online** — search Google Scholar, review results, download open-access PDFs
2. **Searching local papers** — full-text search across indexed PDFs using FTS5
3. **Reading paper content** — access cached markdown renderings of indexed papers

## When to Use

Use this skill when the user needs to:
- Find a specific academic paper by title, author, or topic
- Download a paper PDF for local use
- Search through a collection of local PDFs by content or metadata
- Read or reference the contents of an indexed paper

Do NOT use for:
- General web searches unrelated to academic papers
- Reading arbitrary PDFs not managed by papergrep

## Prerequisites

`papergrep` must be installed and a database initialized. The papers root
directory is `~/papers`. OpenCode is configured with `external_directory`
permission to read files there from any project.

Verify the setup with:

```bash
papergrep stats
```

If `papergrep` is not found, ask the user to install it before proceeding.

If the command runs but fails with "No papergrep database found", the user
needs to run:

```bash
papergrep init --root ~/papers
papergrep index
```

## Papers Directory Structure

Papers in `~/papers` are organized by venue or journal:

```
~/papers/
├── brain-sciences/    # Brain Sciences journal
├── eurographics/      # Eurographics / Computer Graphics Forum
├── josaa/             # Journal of the Optical Society of America A
├── neurips/           # NeurIPS conference
├── vision-research/   # Vision Research journal
└── my_papers/         # User's own publications
```

When downloading a paper, place it in the appropriate subdirectory based on its
venue. If unsure which subdirectory to use, ask the user. If no matching
subdirectory exists, ask the user whether to create one or place the PDF in an
existing directory.

## Workflow: Finding and Downloading a Paper

**IMPORTANT: Google Scholar rate limiting.** Never run multiple `papergrep
fetch` commands in parallel. Google Scholar aggressively rate-limits and will
serve CAPTCHAs that block all further requests. `papergrep` enforces a 5-second
delay between Scholar requests at the process level, but you must still run
fetch commands sequentially — one at a time, waiting for each to complete before
starting the next. If you need to search for multiple papers, chain the fetches
sequentially.

### Step 1: Search Google Scholar

```bash
papergrep fetch "attention is all you need"
```

This prints numbered results with title, authors, year, venue, citation count,
abstract, and a PDF or publisher URL. It also prints a Google Scholar link at
the bottom for manual browsing.

Use `--limit N` to control the number of results (default 5).

### Step 2: Review the results with the user

Present the results to the user. Ask if any of the listed papers is the one
they want. If none match, share the Google Scholar URL so they can browse
manually.

### Step 3: Download (if open-access)

If the desired paper has a `PDF:` URL in the results, determine the correct
subdirectory based on the venue (see directory structure above) and download
directly into it with `--dest`:

```bash
papergrep download "https://example.com/paper.pdf" --title "Attention Is All You Need" --year 2017 --dest neurips
```

The `--title` flag is required and determines the filename (sanitized to
lowercase with underscores). `--dest` specifies a subdirectory within the
papers root (created automatically if it doesn't exist). The download command
automatically re-indexes after saving the file.

If the paper is paywalled (shows `URL:` instead of `PDF:`), inform the user
and provide the publisher URL so they can access it through institutional login.

## Workflow: Searching Local Papers

Search across all indexed papers by keyword:

```bash
papergrep search "transformer architecture"
```

Results are JSON with `path`, `markdown_path`, `title`, `authors`, `year`, and
`score`. Use filters to narrow results:

```bash
papergrep search "attention" --author "Vaswani" --year 2017 --limit 5
```

## Workflow: Reading Paper Content

**Never read full paper files directly in the main agent context.** Always
delegate to a Task subagent. The subagent reads the full content and returns
only the relevant extract.

Indexed papers have cached markdown under `~/papers/.papergrep/md/` — use the
`markdown_path` field from search results. If `markdown_path` is null (the PDF
may be image-only or corrupt), try re-indexing with `papergrep index --force`.
If it remains null, inform the user that the PDF could not be rendered to
markdown. The paper is still discoverable via full-text search, but its content
cannot be read directly by the agent.

### Citation conventions

**Every claim derived from a paper must cite its source.** Any statement
presented without a citation is indistinguishable from the agent's own
fabrication. When summarizing, analyzing, or answering questions about a paper,
treat citation as mandatory — not optional formatting. If you cannot locate
evidence for a claim in the paper, say so explicitly rather than presenting it
uncited.

The user reads the original PDF side-by-side, so citations must use
**semantic references** — section names and paragraph positions — not markdown
line numbers.

Format: **(Section N.M "Title", paragraph K)** with a direct quote or close
paraphrase. Italicize direct quotes to visually separate them from
surrounding text. Prefer direct quotes for technical wording. For unnumbered
sections, use the title with positional detail.

Good: *"we scale the logits by a learned scalar τ"* (Section 3.2 "Scaled
Attention", first paragraph).
Bad: "The model uses learned scaling" (no location), or (Section 3) (too vague).

**All subagent prompts must include these citation rules** so returned text is
already properly cited. Paste the text of the following block (referred to as
`CITATION_RULES` in the templates below) into every subagent prompt:

> Every claim derived from the paper must cite its source — an uncited
> statement will be treated as fabrication. Cite with (Section N.M "Title",
> paragraph K) and a short direct quote. Italicize direct quotes. Use section
> names and paragraph positions the reader can find in the PDF, NOT markdown
> line numbers. Prefer the paper's exact wording for technical terms. If you
> cannot find evidence for a claim, say so explicitly.

Subagent prompts should also request markdown line numbers for cited passages
so the main agent can do narrow follow-up reads. Keep this separate from the
user-facing citation rules above — it is an inter-agent concern.

### Subagent patterns

**Targeted query** — extract specific information:

```
Task(
  subagent_type="general",
  description="Extract info from paper",
  prompt="Read the paper at <markdown_path>. Answer: <question>.
    <CITATION_RULES>
    Do NOT return full paper contents."
)
```

**Artifact production** — summaries, comparison tables, etc.:

```
Task(
  subagent_type="general",
  description="Summarize paper",
  prompt="Read the paper at <markdown_path>. Produce: <artifact_description>.
    <CITATION_RULES>
    Return the artifact only — no raw paper content."
)
```

### Follow-up reads and metadata

When a subagent returns markdown line numbers, use narrow reads for follow-up:

```python
Read(filePath="<markdown_path>", offset=142, limit=20)  # specific section only
```

For metadata without reading content: `papergrep info /path/to/paper.pdf`

## Troubleshooting

- **`papergrep fetch` hits a CAPTCHA**: Scholar has flagged the IP. papergrep
  will automatically launch Chromium for the user to solve the CAPTCHA. Once
  solved and the browser window is closed, papergrep reads the recovery cookie
  and retries. If this automatic flow fails (e.g., Chromium not available),
  the user can manually solve the CAPTCHA in any browser and provide the `GSP`
  cookie via `papergrep set-cookie "GSP=..."`. Inform the user of what is
  happening and wait for them to complete the CAPTCHA before proceeding.
- **`papergrep fetch` returns no results**: The query may be too specific.
  Share the Google Scholar URL printed at the bottom so the user can browse
  manually.
- **Download fails with a 403 or 404**: The PDF URL may have expired or be
  restricted. Ask the user to download manually and place the PDF in `~/papers`,
  then run `papergrep index`.

## Command Reference

| Command | Purpose |
|---------|---------|
| `papergrep fetch <query>` | Search Google Scholar (single page, max 10 results) |
| `papergrep download <url> --title <title> [--year <year>] [--dest <subdir>]` | Download a PDF into subdir and auto-index |
| `papergrep search <query> [--author X] [--year N] [--limit N]` | Full-text search local index |
| `papergrep search <query> --top` | Return only the top hit as JSON |
| `papergrep search <query> --pdf` | Print only the PDF path of the top hit |
| `papergrep set-cookie "GSP=..."` | Manually provide a Scholar CAPTCHA recovery cookie |
| `papergrep info <path>` | Show metadata for a single PDF |
| `papergrep index [--force] [-- PATHSPEC...]` | Re-scan and update the index; pathspecs limit `--force` to specific files/globs |
| `papergrep stats` | Print index statistics |

## Development Status

`papergrep` is under active development. If a workflow feels clunky or a
missing feature would streamline the current research task, suggest the
improvement to the user. They will relay it to the agent developing papergrep.
