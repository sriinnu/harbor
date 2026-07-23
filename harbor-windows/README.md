# Harbor for Windows

> [!WARNING]
> This is an experimental Tauri prototype. It is not a supported Harbor release and no Windows installer should be published from this directory yet.

The Windows tree is being retained to develop a future system-tray client. It currently has early authentication, settings, Git detection, and tray scaffolding; the repository data experience is incomplete.

## Do not rely on it for

- production use
- managing sensitive credentials
- feature parity with the macOS app
- a stable installer or upgrade path

## Development prerequisites

- Node.js 20+
- Rust stable
- Visual Studio Build Tools with Desktop development with C++

```powershell
cd harbor-windows
npm install
npm run tauri:dev
```

These commands are for contributors validating the prototype. A successful build does not mean the app is release-ready.

## Next milestones

1. Replace remaining legacy RepoBar identifiers and assets.
2. Complete the GitHub repository, pull-request, and issue data layer.
3. Verify credential storage and OAuth failure handling on Windows.
4. Add end-to-end coverage and a signed release pipeline.

For the repository-wide support matrix, see [the platform status document](../docs/platforms.md).
