---
summary: "Local development workflow and supported project boundaries for Harbor."
read_when:
  - Building, testing, or changing Harbor
  - Choosing which platform tree to modify
---

# Development

## Supported development target

The supported target is the native macOS app in `Sources/`, built as a Swift package. The repository also contains Windows, Linux, and web experiments; they are not part of the supported release path.

## Setup and checks

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm check
pnpm test
pnpm build
```

`pnpm check` runs formatting and linting. `pnpm test` runs the Swift test suite. Keep changes narrowly scoped and run the checks relevant to the files you touch.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/Harbor` | macOS app UI and application composition |
| `Sources/HarborCore` | provider, Git, authentication, settings, and shared domain logic |
| `Sources/HarborCLI` | command-line interface |
| `Tests/` | Swift tests |
| `Scripts/` | build, test, release, and developer utilities |
| `docs/` | public project documentation |

## Documentation rule

Update the relevant document in `docs/` whenever a command, setup requirement, security assumption, or release process changes.
