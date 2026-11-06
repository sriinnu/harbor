---
summary: "Harbor release runbook: one-time setup, the release command, verification and recovery."
read_when:
  - Preparing or validating a Harbor release
  - Touching anything under Scripts/ that signs, notarizes or publishes
---

# Releasing Harbor

Harbor releases are built, signed, notarized and published **from your Mac**
by `Scripts/release.sh`, with you present: the tag and commits are signed with
the hardware security key. CI never holds signing or notary secrets. The flow
is ported from Runic, with the Homebrew step from tokmeter.

## One-time setup

1. **Developer ID certificate** in your login keychain
   (`security find-identity -v -p codesigning` lists it).
2. **Local secrets**, outside the repo, in `~/.config/harbor/local.env`
   (or a gitignored `.harbor.local.env` in the checkout):

   ```sh
   APP_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
   APP_STORE_CONNECT_KEY_ID=...
   APP_STORE_CONNECT_ISSUER_ID=...
   APP_STORE_CONNECT_API_KEY_P8="<the full text of your AuthKey_<KEYID>.p8 file>"
   SPARKLE_PRIVATE_KEY_FILE="$HOME/.config/harbor/sparkle_private_key"
   ```

   Notarization uses an App Store Connect API key, never an Apple ID password.
3. **Sparkle key** (once per app, under its own Keychain account `harbor`):

   ```sh
   HARBOR_KEY_SETUP_CONFIRM=generate Scripts/generate-keys.sh
   generate_keys --account harbor -x ~/.config/harbor/sparkle_private_key
   chmod 600 ~/.config/harbor/sparkle_private_key
   ```

   The first command writes the public key to `Config/sparkle-public-key`;
   commit that file. Sparkle's tools come from the SwiftPM artifact
   (`build/macos/.build/artifacts/sparkle/Sparkle/bin`); the scripts find them.

## Every release

1. On a branch: bump `Config/version.env` (`MARKETING_VERSION`, and
   `BUILD_NUMBER` above the last appcast build), bump `package.json` to the
   same version, and finalize the top `CHANGELOG.md` section to
   `## X.Y.Z — YYYY-MM-DD`. PR, squash-merge.
2. On `main`, pulled and clean:

   ```sh
   Scripts/release.sh --check   # every gate, changes nothing
   Scripts/release.sh           # the release
   ```

`release.sh` runs, in order:

| Step | What | Stops if |
|---|---|---|
| Preflight | tools, clean `main` == `origin/main`, versions agree, changelog final, appcast monotonic, Sparkle keys match, identity and notary key present, tag free | any gate fails |
| Verify | `Scripts/verify.sh`: strict build (warnings are errors), SwiftLint, tests, shellcheck | any warning, violation, failing, crashed or empty test run |
| Build | `Scripts/sign-and-notarize.sh`: universal build, inside-out Developer ID signing, notarize (API key; retries only an aborted upload), staple, `spctl`, dSYM UUIDs match | notarization isn't Accepted |
| Tag | `vX.Y.Z`, signed and verified, pushed | signature doesn't verify |
| Draft release | zip + dSYM on a **draft** GitHub release | |
| Appcast | `make_appcast.sh`, verified against the local zip, deltas uploaded, assets checked | signature or length mismatch |
| Publish | draft → published (immutable), appcast re-verified against the public URL | public bytes differ |
| Appcast PR | branch `sriinnu/appcast-X.Y.Z` → PR on `main` | |
| Cask | `update-homebrew-cask.sh`: sha256 of the **released** zip, signed commit, PR on `sriinnu/homebrew-tap` | (best effort; rerun the script) |

## Finish and verify

- Merge the appcast PR. Until then, existing installs don't see the update.
- `spctl -a -vv /Applications/Harbor.app` says *Notarized Developer ID*;
  `xcrun stapler validate` passes; `brew fetch --cask sriinnu/tap/harbor` passes.
- Optional live update test in an isolated folder (never touches `/Applications`):
  `RUN_SPARKLE_UPDATE_TEST=1 Scripts/test_live_update.sh vPREV vX.Y.Z`.
- Update Harbor's row in harness-docs `websites/harness/VERSIONS.md`.

## If something fails

- **Before the tag**: nothing is public. Fix and rerun.
- **Tag pushed, release still a draft**: delete the draft, fix, and release the
  next patch version. Tags are immutable (ruleset); never move or force-push one.
- **Published**: releases are immutable. Ship a fixed `X.Y.Z+1`.
- **Cask step failed**: the release is fine; rerun `Scripts/update-homebrew-cask.sh X.Y.Z`.

## Rules

- Never commit signing material. `.gitignore` blocks keys, certs, `.env` and
  release artifacts as a backstop.
- The bundle id is `com.sriinnu.harbor` everywhere: Info.plist, cask `zap`, Sparkle caches.
- The app is not sandboxed (local Git needs `~/.ssh` and `~/.gitconfig`); hardened
  runtime is always on. Entitlements: `Sources/Harbor/Resources/Harbor.entitlements`.
