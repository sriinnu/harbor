# Harbor for Windows: prototype quick start

> [!WARNING]
> This starts an experimental contributor build. It is not an installation guide for end users.

## Prerequisites

- Node.js 20+
- Rust stable
- Visual Studio Build Tools with Desktop development with C++

## Run

```powershell
cd harbor-windows
npm install
npm run tauri:dev
```

Run the Rust checks before changing the platform code:

```powershell
cd src-tauri
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```

The Windows client still needs its repository data layer, secure OAuth validation, release packaging, and end-to-end tests. See [README.md](README.md) and [the platform status](../docs/platforms.md).
