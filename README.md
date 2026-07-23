# Harbor

**A calm, native menu-bar view of the development work that matters.**

Harbor is a macOS app for keeping selected repositories close: source-control activity, pull requests, issues, CI/workflow state, releases, and local Git status—without living in a browser tab.

> [!WARNING]
> Harbor is an early macOS-first project. The Windows, Linux, and web directories are experimental scaffolding, not supported releases. GitLab sign-in is not implemented yet.

## Status

| Area | Status |
| --- | --- |
| macOS menu-bar app | Active development |
| GitHub | Supported with user-supplied OAuth credentials |
| Azure DevOps | Implemented; needs real-world validation |
| Local Git | Implemented |
| GitLab | UI present; sign-in is not implemented |
| Windows, Linux, web | Experimental / unsupported |

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 26.1 with Swift 6.2
- Node.js 22+ with Corepack enabled

## Build from source

```bash
git clone https://github.com/sriinnu/harbor.git
cd harbor
corepack enable
pnpm install --frozen-lockfile
pnpm build
```

Build output is kept under `build/macos/`. To run the test suite:

```bash
pnpm test
```

## First run

Harbor needs a GitHub OAuth application you control. Create one in GitHub Developer Settings, configure the callback URL as `http://127.0.0.1:53682/callback`, then enter its client ID and client secret in Harbor's Account settings. Credentials and resulting tokens are stored in the macOS Keychain.

See the [getting-started guide](docs/getting-started.md) for the setup flow and [security notes](docs/security.md) before using it with a sensitive account.

## CLI

The CLI shares Harbor's local configuration and Keychain credentials. Run it through the project during development:

```bash
pnpm harbor -- status
pnpm harbor -- repos --limit 10
```

See the [CLI reference](docs/cli.md) for commands and options.

## Contributing

Read the [development guide](docs/development.md) and [contributing guide](docs/contributing.md). Please do not open an issue containing credentials, repository URLs you cannot disclose, or diagnostic output with tokens.

## License

[MIT](LICENSE) © 2026 Srinivas Pendela.
