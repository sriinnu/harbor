<div align="center">

<img src="assets/logo.png" alt="Harbor" width="180" />

# Harbor

**Your development work, safely docked in the menu bar.**

</div>

---

Harbor answers one question from the menu bar, without opening a browser
tab: **what needs me right now?** Pin the repositories that matter and see
their CI, pull requests, releases and local Git state at a glance.

> **Status: pre-release.** There is no signed build, Homebrew cask or release
> download yet. The first signed and notarized release is in progress. Until
> then, build from source.

## What works today

- **GitHub**: pinned repositories with CI status, pull requests, issues,
  Actions workflow runs, releases, tags, branches, commits and your
  contribution heatmap.
- **Local Git**: repos found under your projects folder, with branch,
  ahead/behind, dirty state and fast-forward sync.
- **Sign-in** with a one-time code at github.com/login/device. Harbor ships no
  client secret. GitHub Enterprise works with your own OAuth app.
- **CLI**: `harborcli repos`, `harborcli pulls`, `harborcli local --sync` and
  more for scripts.
- **Private**: tokens stay in your macOS Keychain. No analytics, no tracking.

In progress: GitLab and Azure DevOps in the menu (the clients exist, the menu
doesn't use them yet), a "Needs you" triage section, and themes.

Requires macOS 15 or later.

## Build from source

```bash
git clone https://github.com/sriinnu/harbor.git
cd harbor
./Scripts/build.sh
```

CLI reference: [docs/cli.md](docs/cli.md)

## License

MIT, © 2026 Srinivas Pendela. See [LICENSE](LICENSE).
