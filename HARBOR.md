# Harbor — your GitHub work, safely docked in the menu bar

Harbor keeps your GitHub work close without pulling you into a browser.  
Pin the repositories that matter and get a calm, glanceable view of CI, releases, activity, and local Git state—right from the macOS menu bar.

Think of Harbor as your **home port**: everything important in one place, always in sight, never noisy.

![Harbor screenshot](docs/assets/harbor.png)

**CI status** • **Releases** • **Activity & traffic** • **Local Git state**

---

## Install

### Homebrew (recommended)

```bash
brew install --cask steipete/tap/harbor
```
### Download


Features
	•	Live repo cards with CI status, recent activity, releases, and rate-limit awareness.
	•	Rich submenus for pull requests, issues, releases, workflow runs, discussions, tags, branches, and commits.
	•	Global activity feed plus an optional contribution heatmap header (optional per-repo heatmaps).
	•	Local Git state in the menu: branch, ahead/behind, dirty files, and worktrees with quick actions.
	•	Pinned/hidden repos, menu filters, and configurable sorting.
	•	Fast native UI with caching, layout reuse, and debounced refresh.
	•	Sparkle auto-updates for signed builds.
	•	Bundled CLI (harbor) for quick listings and automation (JSON or plain output).

⸻

Local projects & sync

Point Harbor at a local projects folder (for example, ~/Projects). Harbor scans the folder, matches repos to GitHub, and shows local branch + sync state right in the menu.

Optional auto-sync keeps clean repos up to date using fast-forward only, with:
	•	configurable fetch cadence
	•	no force pulls
	•	a subtle notification on successful sync

No surprises. No interference.
⸻
Authentication

Harbor signs in via browser OAuth and stores tokens securely in the macOS Keychain.
	•	Supports GitHub.com and GitHub Enterprise (HTTPS)
	•	No tokens are logged
    •	Sign out anytime to revoke access
⸻
CLI

Harbor ships a bundled CLI (harbor) for quick overviews and automation.
Get a list of your pinned repos:

```bash
harbor login
harbor repos --releases
harbor repos --releases --plain   # no colors, no links, no URLs
harbor repos --json            # JSON output
```
⸻
Heads up

This is an early public release (v0.1.0). There is still plenty to polish and expand, so expect rough edges and rapid iteration.

⸻

Roadmap (directional)

Harbor is designed to grow without turning into a notification engine.

Ideas that fit Harbor’s “home port” philosophy:
	•	Repo health summaries (stale PRs, failing CI streaks, blocked work).
	•	Quiet indicators for important state changes (badge-only, opt-in).
	•	Release and milestone horizon view.
	•	Deeper local Git awareness (branch age, drift, related PRs).
	•	iOS companion (read-only at a glance).
	•	Windows taskbar version with the same mental model.
	•	Shared repo sets for teams and on-call contexts.

## Docs

    