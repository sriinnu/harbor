# Harbor Web

> [!WARNING]
> Harbor Web is an experimental Next.js prototype. It is not a hosted Harbor product and is not approved for production deployment.

This directory contains an earlier web exploration of repository management. It has its own runtime, database, and OAuth model; it does not share the macOS application's release path.

## Current constraints

- Documentation and dependency versions need reconciliation.
- The checked-in CI workflow expects scripts that are not declared in `package.json`.
- The OAuth token migration must be run with an explicit server-side encryption key before any hosted sign-in is enabled.
- No production deployment process or support commitment exists.

Do not deploy this app with real credentials or private repository data until those gaps are closed.

## Contributor-only setup

If you are working specifically on the web prototype, inspect `.env.example`, create an isolated development database, and use credentials created solely for local development. Never commit `.env` files or copied production secrets.

For repository-wide platform scope, see [the platform status](../docs/platforms.md).
