# Contributing to Harbor

First off, thank you for considering contributing to Harbor! It's people like you that make Harbor such a great tool.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Pull Request Process](#pull-request-process)
- [Style Guidelines](#style-guidelines)
- [Community](#community)

## Code of Conduct

This project and everyone participating in it is governed by respect, kindness, and professionalism. By participating, you are expected to uphold these values.

### Our Standards

- Be respectful and inclusive
- Accept constructive criticism gracefully
- Focus on what is best for the community
- Show empathy towards other community members

## Getting Started

### Issues

- **Bug Reports**: Check if the issue already exists before creating a new one
- **Feature Requests**: Discuss major changes in an issue first
- **Questions**: Use GitHub Discussions for questions about usage

### Good First Issues

Look for issues labeled `good-first-issue` - these are great for newcomers!

## How Can I Contribute?

### Reporting Bugs

When reporting bugs, please include:

- **Clear description**: What happened vs what you expected
- **Steps to reproduce**: Detailed steps to reproduce the issue
- **Environment**:
  - OS version (macOS 15.1, Windows 11, etc.)
  - Harbor version
  - Build environment (if building from source)
- **Screenshots/Logs**: Visual proof and relevant logs (redact sensitive info)
- **Minimal reproduction**: If possible, a minimal example that demonstrates the bug

**Bug Report Template**:

```markdown
**Description**
A clear description of the bug.

**Steps to Reproduce**
1. Go to '...'
2. Click on '...'
3. See error

**Expected Behavior**
What should happen.

**Actual Behavior**
What actually happens.

**Environment**
- OS: macOS 15.1
- Harbor Version: 0.1.0
- Build: Release/Debug

**Screenshots**
If applicable, add screenshots.

**Additional Context**
Any other relevant information.
```

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion:

- **Use a clear title**: Summarize the suggestion
- **Detailed description**: Explain the feature and why it's useful
- **Use cases**: Provide concrete examples
- **Alternatives**: Consider alternative approaches
- **Platform considerations**: Think about cross-platform implications

**Feature Request Template**:

```markdown
**Problem Statement**
What problem does this solve?

**Proposed Solution**
How should this work?

**Alternatives Considered**
What other approaches did you consider?

**Platform Impact**
How does this affect macOS, Windows, Linux?

**Additional Context**
Mockups, examples, references.
```

### Contributing Code

1. **Fork the repository**
2. **Create a branch**: `git checkout -b feature/amazing-feature`
3. **Make changes**: Write code, add tests, update docs
4. **Test thoroughly**: Ensure all tests pass
5. **Commit**: Follow commit message guidelines
6. **Push**: `git push origin feature/amazing-feature`
7. **Open Pull Request**: Describe your changes clearly

### Contributing Documentation

Documentation improvements are always welcome:

- Fix typos and grammar
- Clarify confusing sections
- Add examples and tutorials
- Update screenshots
- Improve API documentation

## Development Setup

### macOS Development

**Prerequisites**:
- macOS 15.0+ (Sequoia)
- Xcode 16.2+
- Command Line Tools: `xcode-select --install`

**Setup**:

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/Harbor.git
cd Harbor

# Add upstream remote
git remote add upstream https://github.com/sriinnu/Harbor.git

# Build
./Scripts/build.sh

# Run
open build/Build/Products/Debug/Harbor.app
```

**Testing**:

```bash
# Run tests
swift test

# Run specific test
swift test --filter HarborTests.RepositoryTests

# Run with coverage
swift test --enable-code-coverage
```

### Windows Development

**Prerequisites**:
- Windows 10 (1809+) or Windows 11
- [Rust](https://rustup.rs/) (latest stable)
- [Node.js](https://nodejs.org/) 18+ LTS
- [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/) 2019+

**Setup**:

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/Harbor.git
cd Harbor/harbor-windows

# Install dependencies
npm install

# Run in development mode
npm run tauri dev
```

**Testing**:

```bash
# Rust tests
cd src-tauri
cargo test

# Frontend tests
npm test

# Linting
cargo clippy
npm run lint
```

### Code Style

#### Swift (macOS)

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use SwiftLint: `swiftlint`
- 4 spaces for indentation
- Max line length: 120 characters
- Use meaningful variable names
- Add documentation comments for public APIs

**Example**:

```swift
/// Fetches repositories for the authenticated user.
///
/// - Parameter completion: Called when the fetch completes
/// - Returns: A cancellable request token
func fetchRepositories(completion: @escaping (Result<[Repository], Error>) -> Void) -> Cancellable {
    // Implementation
}
```

#### Rust (Windows)

- Follow [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- Use `cargo fmt` for formatting
- Use `cargo clippy` for linting
- 4 spaces for indentation
- Add documentation comments for public APIs

**Example**:

```rust
/// Fetches repositories for the authenticated user.
///
/// # Errors
/// Returns an error if the API request fails.
pub async fn fetch_repositories(&self) -> Result<Vec<Repository>, Error> {
    // Implementation
}
```

#### TypeScript/React (Windows Frontend)

- Follow [Airbnb JavaScript Style Guide](https://github.com/airbnb/javascript)
- Use ESLint + Prettier
- 2 spaces for indentation
- Functional components with hooks
- TypeScript strict mode

**Example**:

```typescript
interface RepositoryCardProps {
  repository: Repository;
  onPin: (id: string) => void;
}

export const RepositoryCard: React.FC<RepositoryCardProps> = ({ repository, onPin }) => {
  // Implementation
};
```

### Commit Messages

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples**:

```
feat(macos): add dark mode support for menu bar

fix(windows): resolve OAuth callback timeout issue

docs: update installation instructions for Windows

test(core): add unit tests for repository sync
```

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation updates
- `refactor/description` - Code refactoring
- `test/description` - Test additions/updates

**Examples**:
- `feature/gitlab-integration`
- `fix/oauth-redirect-error`
- `docs/update-build-instructions`

## Pull Request Process

### Before Submitting

1. **Update Documentation**: README, docs/, inline comments
2. **Add Tests**: Unit tests for logic, integration tests for features
3. **Run Tests**: Ensure all tests pass locally
4. **Update Changelog**: Add entry to CHANGELOG.md
5. **Screenshots**: For UI changes, include before/after screenshots
6. **Rebase**: Rebase on latest main branch

### PR Template

```markdown
## Description
Brief description of changes.

## Type of Change
- [ ] Bug fix (non-breaking change)
- [ ] New feature (non-breaking change)
- [ ] Breaking change (fix or feature that breaks existing functionality)
- [ ] Documentation update

## Testing
Describe testing performed:
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing on macOS
- [ ] Manual testing on Windows

## Screenshots
If applicable, add screenshots showing:
- Before (current behavior)
- After (new behavior)

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings
- [ ] Tests added/updated and passing
- [ ] CHANGELOG.md updated
- [ ] Commits are clean and well-described

## Related Issues
Closes #<issue_number>
```

### PR Review Process

All submissions require code review. We look for:

- **Correctness**: Does it work as intended?
- **Code Quality**: Is it clean, readable, maintainable?
- **Tests**: Adequate test coverage?
- **Documentation**: Is it well-documented?
- **Security**: Any security implications?
- **Performance**: Performance impact?
- **Cross-Platform**: Works on all supported platforms?

### After Review

1. **Address Feedback**: Respond to all review comments
2. **Update Code**: Make requested changes
3. **Push Updates**: Push new commits to the same branch
4. **Request Re-review**: Ask reviewers to check again
5. **Squash Commits**: Clean up commit history before merge

## Style Guidelines

### General Principles

- **Keep it simple**: Don't over-engineer
- **Be consistent**: Follow existing patterns
- **Think cross-platform**: Consider all platforms
- **Write tests**: Test your code thoroughly
- **Document**: Make it easy for others to understand

### UI/UX Guidelines

- **Calm Design**: No noisy notifications or animations
- **Glanceable**: Information should be quick to understand
- **Consistent**: Follow platform conventions
- **Accessible**: Consider accessibility needs
- **Performant**: Keep UI responsive

### API Design

- **Consistent naming**: Use clear, descriptive names
- **Error handling**: Handle errors gracefully
- **Documentation**: Document all public APIs
- **Backwards compatibility**: Don't break existing APIs
- **Type safety**: Use strong typing where possible

## Testing

### Test Coverage

We aim for 80%+ test coverage. Write tests for:

- **New features**: All new functionality
- **Bug fixes**: Prevent regressions
- **Edge cases**: Handle unusual scenarios
- **Error paths**: Test error handling

### Testing Guidelines

- **Unit tests**: Test individual functions/classes
- **Integration tests**: Test feature workflows
- **UI tests**: Test user interactions (where applicable)
- **Performance tests**: For performance-critical code

### Running Tests

```bash
# macOS
swift test                              # All tests
swift test --filter TestName           # Specific test
swift test --enable-code-coverage      # With coverage

# Windows
cargo test                             # Rust tests
npm test                               # Frontend tests
npm test -- --coverage                 # With coverage
```

## Project Structure

Understanding the codebase structure:

```
Harbor/
├── Sources/
│   ├── Harbor/           # macOS SwiftUI app
│   ├── HarborCore/       # Shared business logic
│   └── HarborCLI/        # Command-line interface
├── Tests/                # Test suites
├── harbor-windows/       # Windows Tauri app
│   ├── src/              # React frontend
│   └── src-tauri/        # Rust backend
├── docs/                 # Documentation
└── Scripts/              # Build scripts
```

## Release Process

Releases are managed by maintainers, but contributors should:

- Update version numbers in PRs that include them
- Add entries to CHANGELOG.md
- Follow semantic versioning

## Community

### Getting Help

- **GitHub Discussions**: Ask questions, share ideas
- **GitHub Issues**: Report bugs, request features
- **Documentation**: Check docs/ folder

### Communication

- Be respectful and constructive
- Provide context and details
- Search before asking (issue might already exist)
- Follow up on your contributions

## Recognition

Contributors are recognized in:

- **README.md**: Acknowledgments section
- **Release notes**: Notable contributions
- **GitHub**: Automatic contributor listing

## License

By contributing to Harbor, you agree that your contributions will be licensed under the MIT License.

---

## Questions?

If you have questions about contributing, feel free to:

- Open a [GitHub Discussion](https://github.com/sriinnu/Harbor/discussions)
- Open an issue with the `question` label
- Check existing documentation

**Thank you for contributing to Harbor!** Every contribution, no matter how small, helps make Harbor better for everyone.

---

<p align="center">
  <strong>Happy Contributing!</strong><br>
  Made with ❤️ by the Harbor community
</p>
