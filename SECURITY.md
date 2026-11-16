# Security

## Reporting a vulnerability

Report it privately through GitHub: **Security → Report a vulnerability** on this repository. Please don't open a public issue, discussion or pull request for it.

Include what you found, the version (Harbor → Settings → About), and steps to reproduce. Leave out real tokens, personal access tokens, Keychain items or account files; a redacted sample is enough.

You'll get an acknowledgement within a few days. Fixes ship in a patch release, and the changelog credits you unless you'd rather it didn't.

## Supported versions

Only the latest release gets security fixes. Harbor updates itself through Sparkle, and the Homebrew cask follows the same release.

## How Harbor handles your credentials

- GitHub sign-in uses the OAuth device flow; the app holds no client secret.
- Tokens (GitHub, Azure DevOps, GitLab) live only in the macOS Keychain, one item per account. They are never written to settings files, logs or UserDefaults.
- Harbor talks to the services you connect (GitHub or your GitHub Enterprise host, Azure DevOps, GitLab) and to its own update feed. It has no analytics or telemetry.

## How releases are protected

- Release builds are signed with a Developer ID certificate, run with the hardened runtime, and are notarized by Apple. Sparkle updates are verified with an EdDSA key.
- Every release has a signed tag, and tags can't be moved or deleted. Published GitHub releases are immutable: their tag and assets can't be changed afterwards.
- `main` changes only through pull requests with passing CI and signed commits.
- CI holds no signing or notarization secrets; releases are built, signed and notarized on the maintainer's machine.
