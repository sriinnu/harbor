---
summary: "Release gates for a future public Harbor macOS build."
read_when:
  - Preparing or validating a Harbor release
  - Running packaging, signing, or update tooling
---

# Release checklist

Harbor does not yet have a verified public release pipeline. Do not publish a release, Homebrew cask, or update feed until every gate below passes.

## Source and security gates

- All committed credentials have been revoked and removed from current source **and Git history**.
- GitHub secret scanning and push protection are enabled.
- `pnpm check` and `pnpm test` pass on the release commit.
- The macOS CI workflow runs the tests; no test step is deliberately skipped.
- The release notes accurately label unsupported platforms and unfinished integrations.

## macOS distribution gates

- Version/build metadata is consistent across the app bundle, release tag, and artifact names.
- A clean machine can build the release artifact.
- The app is signed with the intended Developer ID, notarized, and stapled.
- `spctl --assess --verbose` accepts the final app.
- Sparkle's appcast URL and public key are real release values, not placeholders; generate/sign using the official Sparkle tools and keep the private key outside the repository.
- A test install upgrades from the previous build and can roll back safely.
- The GitHub release contains checksums and release notes.

## Platform gate

Only advertise macOS in a public release until Windows, Linux, and web each meet the separate criteria in [platforms.md](platforms.md).
