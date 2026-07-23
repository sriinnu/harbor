---
summary: "Harbor CLI command reference for the macOS development build."
read_when:
  - Using or documenting Harbor CLI commands
  - Updating CLI flags or output
---

# Harbor CLI

The public command interface is `harbor`. When working from this repository, run it with:

```bash
pnpm harbor -- status
pnpm harbor -- repos --limit 10
```

The CLI uses the same Keychain credentials and settings as the macOS app. Complete GitHub sign-in in Harbor first, or provide your own OAuth credentials to `login`.

## Help

- `harbor help`
- `harbor <command> --help`

## Output options

- `--json` / `--json-output` / `-j`: JSON output.
- `--plain`: plain table without links, colors, or URLs.
- `--no-color`: disable color output.

## Commands

- `repos` (default): list repositories by activity, PRs, issues, and stars.
- `repo <owner/name>`: show a repository summary.
- `issues <owner/name>`: list open issues.
- `pulls <owner/name>`: list open pull requests.
- `local`: scan a local project directory for Git repositories.
- `refresh`: refresh pinned repositories with current settings.
- `contributions`: fetch a user's contribution heatmap.
- `login`: browser OAuth login; accepts `--host`, `--client-id`, `--client-secret`, and `--loopback-port`.
- `logout`: clear stored credentials.
- `status`: show login state.

Use `--help` for the current flags and validation rules for each command. Do not place an OAuth secret directly in shell history; use the macOS app's Account settings where practical.
