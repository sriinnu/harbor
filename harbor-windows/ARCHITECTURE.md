# Harbor for Windows architecture

> [!WARNING]
> Experimental design notes. This is not a parity claim or release specification.

The Windows prototype uses a Tauri 2 application with a React/TypeScript frontend and Rust platform services. The intended boundaries are:

- `src/`: UI and Tauri command clients
- `src-tauri/src/auth/`: OAuth and PKCE experiments
- `src-tauri/src/platform/`: credential storage, callback, settings, and Git location
- `src-tauri/src/commands/`: Rust commands exposed to the UI
- `src-tauri/src/tray/`: system-tray behavior

The prototype is not yet connected to a complete Harbor repository-data layer. Any feature or security claim must be backed by executable tests before the Windows target is promoted beyond experimental status.

See [README.md](README.md) for contributor setup and [the platform status](../docs/platforms.md) for release gates.
