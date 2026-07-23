---
summary: "Contribution guidelines for Harbor."
read_when:
  - Opening a Harbor issue or pull request
  - Making a contribution
---

# Contributing

Small, focused pull requests are easiest to review. Include:

1. A short explanation of the user-visible change.
2. Tests or a reason tests are not practical.
3. Documentation changes when behavior, setup, security, or release steps change.

Before opening a pull request, run the relevant checks:

```bash
pnpm check
pnpm test
```

## Issues

Use issues for reproducible bugs and concrete feature proposals. Never include OAuth credentials, personal access tokens, private repository names, or full diagnostics that could contain them.

## Platform scope

macOS is the active target. Windows, Linux, and web work is welcome only when its experimental status and documentation remain accurate.
