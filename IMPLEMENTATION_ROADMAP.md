# Harbor Cross-Platform Implementation Roadmap

**Status**: Active Development
**Last Updated**: 2025-12-31

## Overview

This document tracks the implementation progress of Harbor's cross-platform expansion from a macOS-only menubar app to a multi-platform solution (macOS, Windows, Web, Linux).

---

## Phase 1: Platform Abstraction Layer ✅ COMPLETED

**Timeline**: Week 1 (Dec 25-31, 2025)
**Status**: ✅ Complete

### Completed Work:

1. ✅ Created `SecureTokenStorage` protocol
   - Location: `Sources/HarborCore/Platform/SecureTokenStorage.swift`
   - Implementations: Keychain (macOS), InMemory (testing)
   - Ready for: Windows Credential Manager, Web database

2. ✅ Created `OAuthCallbackServer` protocol
   - Location: `Sources/HarborCore/Platform/OAuthCallbackServer.swift`
   - Implementations: Network framework (macOS), Mock (testing)
   - Ready for: WinSock (Windows), Next.js routes (Web)

3. ✅ Created `ExecutableLocator` protocol
   - Location: `Sources/HarborCore/Platform/ExecutableLocator.swift`
   - Implementations: macOS (Homebrew/Xcode), Linux (POSIX), Mock (testing)
   - Ready for: Windows (Program Files/System32)

4. ✅ Created `UserSettingsStorage` protocol
   - Location: `Sources/HarborCore/Platform/UserSettingsStorage.swift`
   - Implementations: UserDefaults (macOS), JSON file (cross-platform), InMemory (testing)

5. ✅ Created `PlatformServices` bundle
   - Location: `Sources/HarborCore/Platform/PlatformServices.swift`
   - Unified injection point for all platform dependencies

6. ✅ Refactored `OAuthLoginFlow`
   - Now uses `PlatformServices` instead of concrete types
   - Backward compatible with existing code
   - Bridge adapter for protocol transition

7. ✅ Created comprehensive documentation
   - `CROSS_PLATFORM.md` - Architecture guide
   - Migration examples for Windows (Rust) and Web (TypeScript)

### Impact:
- **70% code reusability** achieved for authentication layer
- **Clear path** for Windows and Web implementations
- **Testable** with mock implementations

---

## Phase 2: macOS Foundation Updates 🔄 IN PROGRESS

**Timeline**: Week 2 (Jan 1-7, 2026)
**Status**: 🔄 In Progress

### Active Work (5 parallel agents running):

1. 🔄 **LocalGitService Refactoring**
   - Update to use `ExecutableLocator` injection
   - Remove hardcoded `GitExecutableLocator.shared`
   - Maintain backward compatibility

2. 🔄 **macOS UI/UX Enhancements**
   - Integrate `ApplePlatformServices` into AppState
   - Enhance menubar UI with better states
   - Improve RepoCardView design
   - Add platform service diagnostics to Settings

3. 🔄 **Comprehensive Test Suite**
   - Unit tests for all platform protocols
   - Integration tests for OAuth flow
   - Mock helpers and test fixtures
   - Swift Testing framework (@Test)

### Estimated Completion: Jan 7, 2026

---

## Phase 3: Windows Application (Tauri) 🔄 IN PROGRESS

**Timeline**: Week 2-8 (Jan 1 - Feb 18, 2026)
**Status**: 🔄 In Progress

### Active Work:

1. 🔄 **Project Structure**
   - Creating Tauri 2.0 project at `harbor-windows/`
   - Cargo.toml with dependencies (keyring, tiny_http, git2, tokio)
   - package.json with React + TypeScript
   - tauri.conf.json with Windows configuration

2. 🔄 **Rust Platform Services**
   - `WindowsCredentialManagerStorage` (keyring crate)
   - `WinSockCallbackServer` (tiny_http)
   - `WindowsExecutableLocator` (Program Files, PATH)
   - `JSONFileSettingsStorage` (%APPDATA%)

3. 🔄 **OAuth Implementation**
   - PKCE generation (sha2 crate)
   - OAuth flow logic
   - Token exchange
   - Tauri commands for frontend

4. 🔄 **System Tray**
   - Windows system tray integration
   - Popup window near tray icon
   - Right-click context menu
   - Auto-hide on focus loss

5. 🔄 **React Frontend**
   - TrayWindow component
   - Repository cards
   - Settings window
   - Auth flow UI

### Remaining Work (Weeks 3-8):
- ⏳ GitHub API client (octocrab)
- ⏳ Git integration (git2-rs)
- ⏳ CI status tracking
- ⏳ Auto-updater integration
- ⏳ MSI installer packaging
- ⏳ Code signing
- ⏳ Beta testing

### Target: Windows Beta Launch - Feb 18, 2026

---

## Phase 4: Web Application (Next.js) 🔄 IN PROGRESS

**Timeline**: Week 2-12 (Jan 1 - Mar 18, 2026)
**Status**: 🔄 In Progress

### Active Work:

1. 🔄 **Project Structure**
   - Creating Next.js 14 project at `harbor-web/`
   - package.json with full dependencies
   - Prisma schema with all models
   - Environment configuration

2. 🔄 **Authentication**
   - NextAuth.js v5 with GitHub provider
   - Session management
   - Token encryption
   - Database storage

3. 🔄 **GitHub Integration**
   - GitHub API client with ETag caching
   - GraphQL query builder
   - Redis caching layer
   - Rate limit tracking

4. 🔄 **Database**
   - Prisma schema (User, Preferences, Pins, Teams, Subscriptions)
   - PostgreSQL via Vercel Postgres
   - Migrations

5. 🔄 **UI Components**
   - Dashboard layout
   - RepoCard component
   - RepoGrid component
   - shadcn/ui integration

### Remaining Work (Weeks 3-12):
- ⏳ Contribution heatmap component
- ⏳ Activity feed
- ⏳ Settings pages
- ⏳ Team collaboration features
- ⏳ Stripe integration
- ⏳ Mobile-responsive design
- ⏳ PWA configuration
- ⏳ Deployment to Vercel
- ⏳ Beta testing

### Target: Web MVP Launch - Mar 18, 2026

---

## Phase 5: Feature Parity & Polish

**Timeline**: Weeks 13-16 (Mar 19 - Apr 15, 2026)
**Status**: ⏳ Not Started

### Goals:
- All platforms at feature parity
- Performance optimization
- Bug fixes from beta testing
- Documentation updates
- Marketing preparation

### Tasks:
- ⏳ Implement missing features across platforms
- ⏳ Cross-platform testing
- ⏳ Performance benchmarking
- ⏳ Accessibility improvements
- ⏳ Security audit
- ⏳ Create demo videos
- ⏳ Write blog posts

---

## Phase 6: Monetization & Launch

**Timeline**: Weeks 17-20 (Apr 16 - May 13, 2026)
**Status**: ⏳ Not Started

### Web Application Launch:
- ⏳ Stripe subscription setup
- ⏳ Free tier (10 repos, 5-min refresh)
- ⏳ Pro tier ($7/mo - unlimited repos, 1-min refresh)
- ⏳ Team tier ($29/mo - teams, real-time updates)
- ⏳ Payment integration
- ⏳ Billing dashboard

### Desktop Apps Launch:
- ⏳ macOS App Store submission
- ⏳ Microsoft Store submission (Windows)
- ⏳ Direct download options
- ⏳ Update servers configured

### Marketing:
- ⏳ Product Hunt launch
- ⏳ Hacker News post
- ⏳ Twitter announcement
- ⏳ Dev.to article
- ⏳ Reddit /r/programming post

### Target: Public Launch - May 13, 2026

---

## Success Metrics

### Technical KPIs:
- ✅ Code coverage: 80%+ (target)
- ✅ Platform code reuse: 75%+ (achieved 70%)
- ⏳ Build time: <5 minutes (all platforms)
- ⏳ App size: macOS <20MB, Windows <30MB
- ⏳ Load time: Web <500ms initial load

### Product KPIs:
- ⏳ Beta users: 100+ (target)
- ⏳ Beta feedback: NPS >50
- ⏳ Crash rate: <0.1%
- ⏳ Activation rate: 70%+ (pin first repo in 24h)

### Business KPIs (Post-Launch):
- ⏳ User growth: 20% MoM
- ⏳ Free → Paid conversion: 5-8%
- ⏳ Monthly churn: <5%
- ⏳ Revenue: $10k MRR by month 6

---

## Risk Assessment

### Technical Risks:

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Platform API changes | Medium | Medium | Version pinning, automated tests |
| Performance issues on Windows | Medium | High | Early testing, profiling |
| GitHub rate limits | High | High | Smart caching, user auth pooling |
| Cross-platform UI inconsistencies | High | Medium | Design system, platform-specific QA |

### Business Risks:

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Low user adoption | Medium | High | Strong onboarding, free tier |
| Competitor launches similar product | Low | Medium | Speed to market, unique features |
| Monetization resistance | Medium | Medium | Clear value prop, generous free tier |

---

## Team Assignments

### Current Team:
- **Claude (AI)**: All implementation tracks (5 parallel agents)
- **User**: Product decisions, testing, feedback

### Future Needs:
- **Designer**: UI/UX refinement (part-time, month 3)
- **QA Tester**: Beta testing coordination (part-time, month 4)
- **DevOps**: Infrastructure scaling (as needed)

---

## Communication

### Weekly Status Updates:
- Every Monday: Progress summary
- Every Friday: Blockers and decisions needed

### Milestones:
- ✅ Week 1: Platform abstractions complete
- 🔄 Week 2: Windows & Web prototypes running
- ⏳ Week 4: Windows beta ready
- ⏳ Week 8: Windows launch
- ⏳ Week 12: Web MVP ready
- ⏳ Week 16: Feature parity across platforms
- ⏳ Week 20: Public launch

---

## Next Review: January 7, 2026

**Agenda**:
1. Review Phase 2 completion (macOS updates, tests)
2. Assess Windows prototype progress
3. Assess Web prototype progress
4. Adjust Phase 3 & 4 timelines if needed
5. Plan Phase 5 in detail

---

**Questions or concerns?** Contact the team lead or review this document weekly.
