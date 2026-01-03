---
summary: "Harbor CLI command reference."
read_when:
  - Using or documenting Harbor CLI commands
  - Updating CLI flags or output
---

# Harbor CLI

Binary name: `harbor`

## Help

- `harbor help`
- `harbor <command> --help`

## Output options

- `--json` / `--json-output` / `-j`: JSON output.
- `--plain`: plain table (no links, no colors, no URLs).
- `--no-color`: disable color output.

## Commands

- `repos` (default): list repositories by activity/PRs/issues/stars.
  - Flags: `--limit`, `--age`, `--release`, `--event`, `--forks`, `--archived`,
    `--scope` (all|pinned|hidden), `--filter` (all|work|issues|prs),
    `--pinned-only`, `--only-with` (work|issues|prs), `--sort` (activity|issues|prs|stars|repo|event).
- `repo <owner/name>`: repository summary.
  - Flags: `--traffic`, `--heatmap`, `--release`.
- `issues <owner/name>`: list open issues (recently updated).
  - Flags: `--limit`.
- `pulls <owner/name>`: list open pull requests (recently updated).
  - Flags: `--limit`.
- `local`: scan local project folder for git repos.
  - Flags: `--root`, `--depth`, `--sync`, `--limit`.
- `refresh`: refresh pinned repositories using current settings.
- `contributions`: fetch contribution heatmap for a user.
  - Flags: `--login`.
- `login`: browser OAuth login.
  - Flags: `--host`, `--client-id`, `--client-secret`, `--loopback-port`.
- `logout`: clear stored credentials.
- `status`: show login state.
