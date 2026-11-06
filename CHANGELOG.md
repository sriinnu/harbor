# Changelog

Release headings are `## X.Y.Z — YYYY-MM-DD`. `Scripts/release.sh` refuses to
release while the top section says Unreleased or doesn't match
`Config/version.env`.

## 0.2.0 — Unreleased

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

### Packaging
- Developer ID signed, notarized, hardened runtime; Sparkle updates from
  github.com/sriinnu/harbor; Homebrew cask `sriinnu/tap/harbor` installs the
  app and the `harborcli` command.
