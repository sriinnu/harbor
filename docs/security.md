---
summary: "Security model, credential handling, and disclosure guidance for Harbor."
read_when:
  - Reviewing Harbor's credential handling
  - Reporting a vulnerability
  - Preparing the repository for public access
---

# Security

## Credential handling

- OAuth tokens and OAuth client credentials are stored in the macOS Keychain.
- Harbor intentionally does not include an OAuth client secret in source code or releases.
- GitHub OAuth is browser-based and uses PKCE with a loopback callback.
- Azure DevOps access uses a user-provided personal access token; use the least privilege practical.

A client secret cannot be kept confidential inside a native application. Until Harbor has a server-side OAuth exchange or a device-flow design, each user should create and supply credentials for an OAuth app they control.

## Before publishing this repository

1. Revoke and rotate any OAuth client secret, PAT, SSH key, signing key, or API key that was ever committed.
2. Remove exposed credentials from **Git history**, not only the current branch. Use a history-rewrite tool such as `git filter-repo`, then force-push carefully.
3. Revoke the affected credential even after rewriting history; clones, forks, caches, and logs may retain it.
4. Review GitHub Actions secrets, release-signing material, Sparkle keys, and generated release artifacts separately.
5. Enable GitHub secret scanning and push protection after the repository becomes public.

## Reporting a vulnerability

Do not open a public issue for a suspected credential leak or vulnerability. Contact the maintainer privately with a minimal reproduction and enough detail to assess impact.
