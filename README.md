<div align="center">

<img src="assets/harbor-icon.png" alt="Harbor app icon: a mooring bollard with a yellow line made fast around it" width="160" />

# Harbor

**Your repos, moored in the menu bar.**

One glance answers one question: *what needs me right now?*

[What it does](#what-it-does) · [Install](#install) · [Privacy](#privacy-and-security) · [Build](#build-from-source) · [CLI](docs/cli.md) · [Contributing](#contributing)

</div>

---

Harbor is a macOS menu-bar app for people who live in more than one repository.
Pin the repos that matter and see their CI, pull requests, releases and local
Git state without opening a browser tab, then jump straight to the thing that
is waiting on you.

## What it does

| | |
|---|---|
| **GitHub** | Pinned repositories with CI status, pull requests, issues, Actions runs, releases, tags, branches, commits, and your contribution heatmap. |
| **Local Git** | Finds the repos under your projects folder: branch, ahead/behind, uncommitted changes, and a safe fast-forward sync. |
| **Sign-in** | A one-time code at github.com/login/device. Harbor ships no client secret. GitHub Enterprise works with your own OAuth app (enter its host as `ghe.example.com`). |
| **CLI** | `harborcli repos`, `pulls`, `issues`, `local --sync` and more, for scripts and terminals. [Reference](docs/cli.md). |
| **Updates** | Signed, notarized builds that update themselves through Sparkle. |

**In progress:** GitLab and Azure DevOps in the menu (their API clients are
written and tested; the menu doesn't use them yet), a "Needs you" section that
ranks what's waiting on you, themes, and the new menu-bar icon.

Requires **macOS 15** or later.

## Install

```bash
brew install --cask sriinnu/tap/harbor
```

The cask installs `Harbor.app` and the `harborcli` command. Harbor updates
itself through Sparkle. Or download the zip from
[Releases](https://github.com/sriinnu/harbor/releases/latest).

## Privacy and security

- **No analytics, no tracking, no server of ours.** Harbor talks only to the
  forges you sign in to.
- **Every secret lives in your system's secure store**, never in settings files
  or logs: tokens, OAuth client credentials, Azure DevOps PATs and GitLab
  tokens all go through one `SecretStore`, which is the login Keychain on macOS
  (local to your Mac, never synced to iCloud).
- **Signed and notarized** with a Developer ID, hardened runtime on. Not
  sandboxed, because local Git needs `~/.ssh` and `~/.gitconfig`.
- Found a vulnerability? Report it privately from the repository's
  **Security** tab ("Report a vulnerability"), not in a public issue.

## Build from source

You need Xcode 26 (Swift 6.2), and Node.js with pnpm for the helper scripts.

```bash
git clone https://github.com/sriinnu/harbor.git
cd harbor
pnpm install
pnpm dev          # build, sign, and launch a dev build
```

`pnpm dev` signs with your Apple Development certificate when you have one (so
the Keychain trusts every rebuild) and labels the build, e.g. "Dev build
0.02.0007", in the menu and in Settings → About.

| Command | What it does |
|---|---|
| `pnpm dev` | Package, sign and relaunch a labelled dev build |
| `pnpm dev:watch` | Hot reload: rebuild and relaunch on every save |
| `pnpm verify` | The full gate: strict build, lint, tests, dependency audit, shellcheck |
| `pnpm test` | Tests only |
| `pnpm harbor repos` | Build and run the CLI |
| `./Scripts/build.sh release` | Plain Xcode release build (not signed for distribution) |

Releases are made with `Scripts/release.sh`; see [docs/release.md](docs/release.md).

## Contributing

Run `pnpm verify` before you push. It's the same gate CI and the release script
run, and it fails on:

- any compiler warning (`HARBOR_STRICT=1` turns them into errors),
- any SwiftLint violation,
- a failing, crashed or empty test run,
- a dependency with a known vulnerability (`pnpm audit`, `cargo audit`),
- shellcheck findings in `Scripts/`.

Commits and tags are signed; `main` only changes through pull requests. The
rules agents and humans both follow are in [AGENTS.md](AGENTS.md).

## Other platforms

`harbor-windows/` and `harbor-linux/` are early Tauri prototypes. **Neither
builds today**, and they are not part of any release.

## License

MIT, © 2026 Srinivas Pendela. Harbor began as a fork of Peter Steinberger's
[RepoBar](https://github.com/steipete/RepoBar) (MIT, © 2025); see [LICENSE](LICENSE).
