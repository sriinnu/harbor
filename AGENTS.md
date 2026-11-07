# Agents

Rules for any coding agent working in this repo: the guarantees you must not break. Release mechanics live in `docs/release.md`; vision, board and architecture live in the harness docs (`docs/harness/`, linked locally, not tracked).

## Git

- `main` takes changes only through pull requests with the required check "macOS (Xcode 26.1)" passing and up to date. Work on a branch, open a PR, squash-merge.
- Sign every commit and tag. Never pass `-c commit.gpgsign=false` or create an unsigned tag. Tags matching `v*` are immutable.
- Never force-push, rewrite history, or delete a branch or tag you didn't create without the maintainer's explicit go.

## Secrets

- Nothing secret is committed, ever: tokens, OAuth client secrets, `.p8` keys, the Sparkle private key, `~/.config/harbor/local.env`, `.harbor.local.env`. `.gitignore` is a backstop, not the guard.
- GitHub sign-in uses the OAuth device flow and needs no client secret in the app. Don't reintroduce one in `AuthDefaults` or anywhere else.
- Every secret goes through `SecretStore` (`Sources/HarborCore/Platform/SecretStore.swift`): the Keychain on macOS and iOS, Credential Manager on Windows and the Secret Service on Linux (Tauri apps, `keyring` / `secret-service`), the Android Keystore on Android. No `SecItem` call anywhere else, and no secret in UserDefaults, settings files or logs. Keychain services: `com.sriinnu.harbor.auth` (GitHub), `.ado` (Azure PATs), `.gitlab`.
- Tokens live in the Keychain (`com.sriinnu.harbor.auth`). Tests use the in-memory store and must never read or write the real Keychain or the user's `~/.config`.

## Quality bar (codebase → static analysis → verification → prose → human review)

- **Run `pnpm verify` (`Scripts/verify.sh`) before every push.** It is the same gate CI runs: strict build (`HARBOR_STRICT=1`, every warning is an error), `swiftlint --strict`, tests (fails on a crashed runner or a runner that ran 0 tests), shellcheck. Green means it printed `verify: all gates passed`.
- **Compiler warnings are findings, not noise.** Sources and Tests build with zero; keep it that way. Several "never used" and "always fails" warnings here have hidden real bugs (four WIQL templates silently ignored their `days:` argument). Fix the cause, don't silence it.
- SwiftLint has zero violations, warnings included. `swiftformat` has not yet been applied repo-wide (board item H-015): don't reformat files you aren't changing, and keep that sweep in its own PR.
- **Tests assert exact output.** `XCTAssertEqual` on the rendered query, string or value, not `contains`. `contains("@Today")` passed for a 30-day query that rendered `@Today`, and `"CONTAINS"` contains `"IN"`.
- **A test must fail on the broken code.** When fixing a bug, run the new test against the old code once and see it fail. When filtering tests, confirm the filter actually matched tests (look for "Executed N tests", N > 0).
- Test fixtures that run `git` must not inherit the user's global hooks or signing config.
- Run parallel builds or tests with their own `--build-path`; shared build dirs make test results lie.

## App

- Bundle id is `com.sriinnu.harbor` everywhere (Info.plist, cask `zap`, Sparkle caches). The CLI is `harborcli`, shipped in `Contents/Helpers/`.
- Not sandboxed: local Git needs `~/.ssh` and `~/.gitconfig`. Hardened runtime is always on; entitlements are in `Sources/Harbor/Resources/Harbor.entitlements`. Don't add entitlements without a reason in the PR.

## Releases

- `Scripts/release.sh` is the only release path, run by the maintainer from a clean `main` with the security key present. `Scripts/release.sh --check` reports every gate and changes nothing; agents may run it.
- CI never holds signing or notary secrets. Don't add a workflow that builds, signs, notarizes or publishes a release.
- Published GitHub releases are immutable. Fix a bad release with a new patch version.

## GitHub Actions

- Pin every action to a full commit SHA with the version in a comment. Dependabot keeps the pins current.
- Workflows default to read-only permissions; grant more per job, and only what that job needs.
