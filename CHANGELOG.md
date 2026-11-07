# Changelog

Release headings are `## X.Y.Z — YYYY-MM-DD`. `Scripts/release.sh` refuses to
release while the top section says Unreleased or doesn't match
`Config/version.env`.

## 0.2.1 — 2026-11-07

### Sign-in
- GitHub sign-in works again. 0.2.0 shipped with the ID of a retired OAuth
  app; Harbor now uses its new app, which needs no client secret.

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
