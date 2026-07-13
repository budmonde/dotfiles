---
name: imgen
description: Generate images from text prompts by preparing an imgen invocation that the user runs in their own shell, avoiding long-running blocking calls inside opencode
---

## What This Skill Does

This skill wraps `imgen`, a small Python CLI that calls `/v1/images/generations` on any OpenAI-compatible endpoint and writes the resulting image bytes to a file on disk.

Image generation is a single blocking HTTP request that typically takes 2-5 minutes against the configured gateway, with no streaming or progress events.
To keep that wait out of opencode's bash tool (where it would block the agent's turn and is liable to be killed by the bash timeout), this skill **does not invoke `imgen` itself**.
Instead, the agent writes the prompt to a file on disk and hands the user a ready-to-run `imgen` command for their own shell.

## When to Use

Use this skill when the user asks for an image:

- "Generate an image of X."
- "Make a 1024x1024 picture of X."
- "I need a reference image of X."
- "Draft a logo / icon / placeholder for X."

Do NOT use for:

- Editing or modifying existing images — `imgen` only calls `/v1/images/generations`, not `/v1/images/edits`.
- Vision *understanding* (describing what's in an image) — that's a chat-model job, not an image-gen job.
- Video generation — out of scope for this CLI.

## Prerequisites

`imgen` must be on the user's `PATH` and three environment variables must be set in their shell:

- `IMGEN_BASE_URL` — base URL of the inference endpoint, including the `/v1` suffix.
- `IMGEN_API_KEY` — bearer token for that endpoint.
- `IMGEN_DEFAULT_MODEL` — default model when `--model` is not supplied (optional but recommended).

If the user reports that `imgen` is not found or that the env vars are missing, point them at the dotfiles setup but do not attempt to install or configure it yourself.

## Workflow: Prepare an Image Generation

### Step 1: Confirm the prompt and the output location

If the user's request is short ("make a cat picture"), ask one clarifying question if it would meaningfully change the output (style, aspect ratio, level of detail).
Otherwise proceed.

Ask the user **where the prompt file and image should be stored** — a directory path.
Do not assume a default.
Once you have the directory, derive a stem from the request (e.g. `nvidia_logo` for "the NVIDIA logo, ..."), confirm the stem with the user if it isn't obvious, and use it for both filenames:

- `<dir>/<stem>.prompt.md` — the prompt as a plain markdown file.
- `<dir>/<stem>.png` — the image, generated next to the prompt.

Pairing the two files by stem keeps provenance trivial: months later, anyone looking at the image can find the prompt sitting beside it.

### Step 2: Write the prompt file

Use the `write` tool to create `<dir>/<stem>.prompt.md` with the prompt text verbatim.
The whole file is treated as the prompt — no frontmatter, no special syntax.
Keep the prompt in plain prose; `imgen` reads the entire file (outer whitespace trimmed) and forwards it unchanged to the model.

If the prompt is short, write it as a single paragraph.
If it has structure (style, composition, lighting, etc.), use paragraphs or a bulleted list — the image model will treat the file as one combined prompt regardless.

### Step 3: Hand the user a dry-run command

Show the user a fenced code block they can paste into their own shell containing the `--dry-run` invocation first.
The dry-run prints the URL, headers (with the API key redacted), and JSON body without making a network call.
It costs nothing and verifies that the prompt file is readable and the request is shaped correctly.

```bash
imgen --dry-run -p <dir>/<stem>.prompt.md -o <dir>/<stem>.png
```

If the user wants a non-default model, size, or count, append the relevant flags (see [Command Reference](#command-reference)).

Tell the user: "Run this first to verify the request, then run the same command without `--dry-run` to generate the image."

### Step 4: Hand the user the real command

Below the dry-run block, give them the real invocation:

```bash
imgen -p <dir>/<stem>.prompt.md -o <dir>/<stem>.png
```

Mention that the call will block their shell for a few minutes with no progress output — that's normal, not a hang.

### Step 5: After the user reports completion

When the user says the image is ready (or they paste the success line back at you), you can proceed.
If the active opencode model is multimodal, you may use the `read` tool to inspect the result.
If the user wants a variation, iterate by editing `<stem>.prompt.md` and re-running, or by creating a new `<stem-v2>.prompt.md`.
Do not overwrite the previous output unless asked.

## Command Reference

| Command | Purpose |
|---------|---------|
| `imgen -p FILE -o PATH` | Generate one image, prompt from FILE, using `IMGEN_DEFAULT_MODEL`. |
| `imgen -o PATH "PROMPT"` | Same, but with the prompt inline as a positional arg (avoid for long prompts — shell quoting). |
| `imgen -m MODEL ...` | Override the model for this invocation. |
| `imgen -s 1024x1024 ...` | Set image size. Common values: `1024x1024`, `1024x1792`, `1792x1024`. |
| `imgen -n 3 -o stem.png ...` | Generate 3 images named `stem.png`, `stem-1.png`, `stem-2.png`. |
| `imgen -q high ...` | Pass a quality hint (model-dependent: `standard`, `hd`, `low`, `medium`, `high`). |
| `imgen --dry-run ...` | Print the request without sending; the API key is redacted. |
| `imgen --timeout 600 ...` | Override the 300-second default timeout for very slow models. |

Exactly one of a positional prompt or `--prompt-file` must be supplied; supplying both is a usage error.

## Exit Codes

- `0` — success.
- `1` — config or usage error (missing env var, missing/empty prompt file, bad arguments).
- `2` — network error (DNS, connection, timeout).
- `3` — API error (non-2xx HTTP response). The server's error message is printed to stderr.
- `4` — malformed response (missing `data`, no `b64_json`, or undecodable base64).

## Edge Cases

- **Server returns a URL instead of base64.** `imgen` requests `response_format: b64_json` but some servers ignore the hint and return `url`.
  In that case `imgen` exits with code 4 and prints the URL.
  Suggest the user fetch with `curl -L -o PATH "$URL"`, or adjust the request and retry.
- **Model rejects the size or quality.** The server returns a 400 with an explanation; surface the message to the user.
  Common cause: a model that supports only square sizes being asked for a non-square one.
- **Long generation times and no progress reporting.** The endpoint is a single blocking HTTP request with no streaming, SSE, or partial-progress signal.
  The client sits silent until the full image returns or the timeout fires.
  A 1024x1024 gpt-image-2 generation against the NVIDIA gateway typically takes 2-4 minutes; the 300-second default handles most cases but heavy models or queue contention can exceed it.
  If the timeout trips, the user can retry with `--timeout 600`.
- **Output directory does not exist.** `imgen` creates parent directories automatically; no extra `mkdir` needed.
- **Prompt file is empty or unreadable.** `imgen` exits with code 1 and a clear error.
  If the user reports this, check the file exists and has non-whitespace content.

## Security Notes

Never echo the value of `IMGEN_API_KEY` in any output, log, or commit.
The `--dry-run` mode redacts it; the user's dry-run output is safe to paste back.
If the user asks "what key am I using" or similar, point them at the env var rather than reading it back.
