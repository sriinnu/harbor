---
summary: "Harbor release checklist: versioning, Sparkle appcast, signing/notarization, and verification."
read_when:
  - Preparing or validating a Harbor release
  - Running package_app/notarize scripts or checking release assets
---

# Release checklist (Harbor)

## ✅ Standard Release Flow (Harbor/VibeTunnel parity)
1) **Version + changelog**
   - Update `version.env` (`MARKETING_VERSION`, `BUILD_NUMBER`).
   - Finalize the top section in `CHANGELOG.md` (no “Unreleased”; header must start with the version).

2) **Run the full release script**
   - `Scripts/release.sh`
   - Builds, signs, notarizes, generates appcast entry + HTML notes from `CHANGELOG.md`, publishes GitHub release, tags/pushes.

3) **Sparkle UX verification**
   - About → “Check for Updates…”
   - Menu only shows “Update ready, restart now?” once the update is downloaded.
   - Sparkle dialog shows formatted release notes (not escaped HTML).

## Signing keys and OAuth (read before any release)
- **Sparkle update-signing key**: create it with `HARBOR_KEY_SETUP_CONFIRM=generate Scripts/generate-keys.sh`, which runs Sparkle's official `generate_keys` and keeps the private key in your login Keychain. Never write it into the repo; `.gitignore` blocks `*.pem`, `*.p8`, `*.p12` and the old `SparklePrivateKey.pem` path as a backstop.
- **GitHub OAuth**: Harbor ships only the public client ID and signs in with GitHub's device flow. Keep **Enable Device Flow** switched on in the OAuth app's settings on GitHub. There is no client secret to inject at build time, and none may be added to source.

## Manual steps (only when re-running pieces)
1) Debug smoke build/tests  
   - `Scripts/compile_and_run.sh`

2) Package + notarize  
   - `Scripts/package_app.sh [debug|release]`
   - Optional notarization: `NOTARIZE=1 NOTARY_PROFILE="Xcode Notary" Scripts/package_app.sh release`
   - Verify: `spctl --assess --verbose build/macos/.build/release/Harbor.app`

3) Release notes (markdown)
   - `Scripts/generate-release-notes.sh <version> > RELEASE_NOTES.md`

4) Post-publish asset check  
   - `Scripts/check-release-assets.sh <tag>` (zip + dSYM present)
