---
summary: "Build Harbor locally and connect a GitHub account using your own OAuth app."
read_when:
  - Setting up Harbor for the first time
  - Configuring GitHub OAuth
---

# Getting started

Harbor is currently a macOS-first project. It requires macOS 15+, Xcode 26.1 / Swift 6.2, and Node.js 22+.

## Build

```bash
git clone https://github.com/sriinnu/harbor.git
cd harbor
corepack enable
pnpm install --frozen-lockfile
pnpm build
```

The build script writes macOS artifacts to `build/macos/`.

## Connect GitHub

Harbor does not bundle an OAuth client secret. Create an OAuth application under [GitHub Developer Settings](https://github.com/settings/developers) and configure:

- Homepage URL: your preferred project URL
- Authorization callback URL: `http://127.0.0.1:53682/callback`

On first launch, open Account settings and enter the client ID and client secret for that OAuth application. Harbor uses a browser-based OAuth flow with PKCE. It stores the credentials and returned tokens in the macOS Keychain.

Treat the client secret like a password: do not commit it, paste it into an issue, or include it in logs.

## Verify

```bash
pnpm test
pnpm harbor -- status
```

The CLI reports `Logged out.` until you have completed the in-app GitHub sign-in.
