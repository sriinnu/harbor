# Changelog

Release headings are `## X.Y.Z — YYYY-MM-DD`. `Scripts/release.sh` refuses to
release while the top section says Unreleased or doesn't match
`Config/version.env`.

## 0.2.3 — Unreleased

### Tower
- A new Tower tab (⌘T) shows every agent worktree across your repos in lanes:
  Needs you, Working, Ready, In review, Leftovers. It reads the agents ledger and
  watches each repo's `.git`, so rows update within a second.
- Each worktree gets a merge forecast against main. The forecast runs in a
  sandbox that can't write to your repos, never runs merge drivers, and says
  "couldn't check" instead of guessing. It needs git 2.41 or later.
- Files changed in two or more live worktrees are flagged before either reaches
  main.
- A retire queue lists worktrees the audit calls safe to remove, shows the dry
  run first, and asks before deleting. The panel stays open until it finishes.

### Pull requests
- A pull request pane says in plain words whether it can merge, and lets you
  resolve threads, update the branch and merge. The confirm names the branch it
  will delete, and is cancelled if the pull request changes while it is open.

### Panel
- Issues, pull requests, releases, runs and branches open as lists in the panel.
- Sync, rebase and fast-forward a local clone from its repo detail.
- Review requests appear in Needs you.
- "All clear" appears only when every repository answered. Otherwise the panel
  says what it couldn't check, and the menu bar light turns into a hollow ring.
- Clean up old workflow runs: keeps the newest 5 of every workflow, deletes one
  per second, stops on a rate limit, and has a Stop button.
- Stars, forks and traffic in each repo; a year-by-month grid for All time.
- More than one project folder.
- A coloured menu bar icon and a new app icon.

### Speed, without caches
- Every cache is gone: no ETag store, no saved repo details, no "fetched
  recently" skips. Leftover cache files from earlier versions are removed.
- Repository counts come from batched GraphQL queries. A refresh now makes 3 REST
  calls instead of about 330, and a cold refresh went from 7.0 s to 4.4 s.
- GraphQL rate limits are recognised and back off, and the banner shows them.
- Signing out or switching accounts clears everything from the old account at
  once.

### Fixes
- Upgrading no longer adds `~/Projects` as a project folder you never chose.
- Azure DevOps: opening the token help also opens your organization's token page.
- CI actions are pinned to current versions, with Dependabot keeping them fresh.

## 0.2.2 — 2026-11-07

### Menu bar
- Harbor's icon shows in the menu bar again, and clicking it opens the menu on
  macOS 27. Harbor now owns its status item directly instead of relying on a
  library that reached into private AppKit classes.
- The icon is the Bollard template glyph: filled when calm, a corner dot and a
  count when a repository needs you, outline only when signed out.
- Settings no longer opens on every launch for people who are signed in.

### Themes
- Six skins, under Settings → Menu → Look: Liquid Glass Native, Harbor Brand
  Navy, Ligne Claire Daylight, Ligne Claire Night Watch, Admiralty Chart and
  Signal Flags High Contrast. Each restyles the menu, heatmaps and Settings.
- The Harbor view: your repositories as boats, moored when clean, listing with
  local drift, in a storm when CI fails, the tide showing two weeks of commits.

### Real numbers
- Each repository shows its open Dependabot alerts by severity, leaked secrets
  and code scanning alerts. Where GitHub won't say, Harbor says "unavailable",
  never zero. `harborcli repo --security` prints the same.
- Traffic and forks appear in each repository's menu.
- A failed pull request lookup no longer shows as 0 PRs, and "last refreshed"
  now means a refresh that finished.
- `harborcli repo --traffic`, `--heatmap` and `--release` work; they were
  silently ignored.

### Updates
- Release notes of earlier versions stay in the update feed.

### Credits
- Harbor began as a fork of Peter Steinberger's RepoBar (MIT); the license and
  README now say so.

## 0.2.1 — 2026-11-07

### Sign-in
- GitHub sign-in works again. 0.2.0 shipped with the ID of a retired OAuth
  app; Harbor now uses its new app, which needs no client secret.

### CLI and polish
- `harborcli local --root` with a folder that doesn't exist is an error, not
  "No repositories found".
- Errors and help name the command `harborcli`.
- The "stats are being generated" notice says Harbor, not a leftover name.

## 0.2.0 — 2026-11-06

First signed release.

### Sign-in and security
- Sign in to GitHub with a one-time code at github.com/login/device. Harbor no
  longer ships an OAuth client secret. Your own OAuth app (e.g. GitHub
  Enterprise) still signs in through the browser.
- Signing in can no longer get stuck on "Signing in…"; you can cancel it, and
  sign-in errors now show in the menu.
- OAuth token responses are no longer written to the diagnostics log.
- A GitHub Enterprise host typed without `https://` (`ghe.example.com`) now
  works; an unusable host shows an error instead of quietly signing in to
  github.com.

### Azure DevOps
- Work-item queries are valid WIQL: "is one of" filters, area and iteration
  paths with backslashes, tag filters, and the first condition of a query.
- Project filters now filter by project, and "last N days" / stale-item queries
  use N instead of today.
- Commit change counts show up.

### CLI
- `harborcli` help and messages use the Harbor name throughout.

### Look
- New app icon: a mooring bollard with a yellow line made fast around it.

### Security
- Every secret (GitHub tokens, OAuth app credentials, Azure DevOps PATs, GitLab
  tokens) is kept in the macOS Keychain through one store, local to your Mac
  and never synced to iCloud.
- Listing Azure DevOps organizations no longer fails when a PAT is saved.
- All known dependency vulnerabilities fixed.

### Local Git
- A missing git or a folder that isn't a repository is reported as such, not
  as "uncommitted changes".

### Packaging
- Developer ID signed, notarized, hardened runtime; Sparkle updates from
  github.com/sriinnu/harbor; Homebrew cask `sriinnu/tap/harbor` installs the
  app and the `harborcli` command.
