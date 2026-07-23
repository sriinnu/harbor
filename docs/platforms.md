---
summary: "Support matrix and public-readiness work by Harbor platform."
read_when:
  - Deciding which Harbor platform to use or work on
  - Preparing a platform-specific release
---

# Platform status

| Platform | Current status | Public-release gate |
| --- | --- | --- |
| macOS | Active development target | Passing tests, signed/notarized build, verified update path |
| Windows | Experimental Tauri prototype | Finish GitHub data layer, rebrand all artifacts, add CI/release tests |
| Linux | Prototype shell | Implement application behavior beyond the starter commands and add package tests |
| Web | Experimental prototype | Reconcile dependencies/docs, add a lockfile and working CI, complete security review |

## macOS

The Swift/SwiftUI app is the only target currently described as usable. It integrates GitHub, Azure DevOps, and local Git. GitLab sign-in is not implemented.

Public-release work is primarily: credentials/history cleanup, test health, release automation verification, and a signed/notarized distribution.

## Windows

The Windows Tauri app is a prototype. Its repository data experience is unfinished and existing docs previously described it as a completed RepoBar product. Do not publish installers or direct users to it until the platform checklist above is complete.

## Linux

The Linux Tauri app currently exposes starter commands rather than Harbor's repository workflow. It is a foundation, not an application release target.

## Web

The web app is a separate Next.js prototype. Its dependencies, documentation, and CI expectations are inconsistent; it is not a hosted Harbor service.

A platform becomes supported only when its own build, test, security, and release path are verified—not when another platform happens to work.
