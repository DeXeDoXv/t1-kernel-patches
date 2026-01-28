# Contributing to Apple T1 Touch Bar Support

Thank you for your interest in contributing! This document provides guidelines for reporting issues, submitting patches, and developing new features.

## Code of Conduct

- Be respectful and inclusive
- Assume good faith
- Focus on the code, not the person
- Help others succeed

## Reporting Issues

### Before Reporting

1. **Check existing issues** - Search GitHub for similar issues
2. **Check documentation** - Review README.md and troubleshooting sections
3. **Verify reproduction** - Can you consistently reproduce the issue?

### Issue Template

```markdown
## Summary
[One-line description of the issue]

## Environment
- Linux distribution: [e.g., Ubuntu 22.04]
- Kernel version: uname -r
- Hardware: [MacBook Pro model and year]

## Steps to Reproduce
1. [First step]
2. [Second step]
3. [...]

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Relevant Logs
[Paste output of: dmesg | tail -50]
[Paste output of: lsmod | grep apple]
```

## Development Setup

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get install build-essential git linux-headers-$(uname -r)

# Fedora
sudo dnf install gcc git kernel-devel

# Arch
sudo pacman -S base-devel git linux-headers
```

### Clone and Setup

```bash
git clone https://github.com/DeXeDoXv/t1-kernel-patches
cd t1-kernel-patches

# Make scripts executable
chmod +x scripts/*.sh kernel/adapt/*.sh
```

## Contributing Code

### Commit Message Guidelines

Follow conventional commits format:

```
<type>(<scope>): <subject>

<body>

Fixes #<issue-number>
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation
- `refactor:` Code refactoring
- `perf:` Performance improvement
- `test:` Adding or updating tests
- `chore:` Build, CI, dependencies

**Examples:**
```
feat(detection): Add support for kernel 6.x HID API changes
fix(installer): Handle missing kernel headers gracefully
docs(readme): Clarify DKMS installation process
```

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation
- `test/description` - Tests

### Pull Request Process

1. **Create branch** from `main`
2. **Make changes** with clear, focused commits
3. **Test thoroughly** - Run on multiple kernels if possible
4. **Update docs** - Modify README if behavior changes
5. **Submit PR** with description

### Code Style

#### Shell Scripts
- Use `#!/bin/bash` (not `/bin/sh`)
- Shellcheck compliance: `shellcheck *.sh`
- Quote variables: `"$var"` not `$var`
- Use `set -euo pipefail` at top of scripts
- Avoid GNU-isms, use POSIX where possible

#### C Code
- Linux kernel style (see `Documentation/process/coding-style.rst`)
- Use `/* comments */` for multi-line, `// comments` for single-line (C99+)
- Include guards: `#ifndef FILE_NAME_H` format
- Proper error handling with goto error labels
- Kernel logging: `pr_info()`, `pr_err()`, `pr_debug()`

#### Documentation
- Markdown format
- Clear, concise language
- Code blocks with language tags: ` ```bash ... ``` `
- Internal links: `[text](path/to/file.md)`
- External links: full URLs

## Testing

### Unit Testing

```bash
# Test feature detection script
./scripts/detect-kernel-features.sh /lib/modules/$(uname -r)/build

# Test with different output formats
OUTPUT_FORMAT=c ./scripts/detect-kernel-features.sh /lib/modules/$(uname -r)/build
OUTPUT_FORMAT=json ./scripts/detect-kernel-features.sh /lib/modules/$(uname -r)/build
```

### Integration Testing

```bash
# Dry-run installation
sudo ./scripts/install-touchbar.sh --dry-run --verbose

# Test on fresh VM/container
docker run -it ubuntu:22.04 bash
[in container] ./scripts/install-touchbar.sh
```

### Kernel Testing

Ideally test patches and drivers on:
- Oldest supported kernel (4.15 if possible)
- Current stable kernel
- Latest development kernel
- Multiple architectures if possible

## Adding Features

### Add Kernel Feature Detection

1. **Edit** `scripts/detect-kernel-features.sh`
2. **Add function** `detect_new_feature()`
3. **Add to FEATURE_NAMES** array
4. **Test all output formats** (C, Make, JSON, Bash)

### Add Distro Support

1. **Update** `scripts/install-touchbar.sh` - `detect_distro()` and `normalize_distro()`
2. **Update** package lists in `install_dependencies()`
3. **Test** on target distribution
4. **Update** README.md supported distros table

### Add Kernel Patch

1. **Generate patch** from kernel source:
   ```bash
   git diff > 0NNN-description.patch
   ```
2. **Place** in `kernel/patches/`
3. **Test** with `kernel/adapt/adaptive-patch.sh`
4. **Document** in README.md and commit message

## Documentation

- Keep README.md up-to-date
- Add inline code comments for complex logic
- Document kernel API assumptions in code
- Explain non-obvious feature detection choices

## Performance Considerations

- Feature detection should be fast (run at build time, not runtime)
- Minimize dynamic allocations in driver
- Use RCU where appropriate for list traversal
- Avoid busy-waiting loops

## Security

- Never run untrusted code without verification
- Use cryptographic checksums for downloads
- Sanitize user input in shell scripts
- Avoid shell injection vulnerabilities
- Keep dependencies minimal

## Licensing

- All code must be compatible with GPL-2.0+
- Include SPDX license identifier in new files
- Use existing copyright where applicable
- Add yourself to file header if making significant changes

## Review Process

1. Maintainer reviews PR for:
   - Code quality and style
   - Kernel version compatibility
   - Documentation completeness
   - Testing evidence
   
2. Feedback provided in comments
3. Author addresses feedback
4. Final approval and merge

## Release Process

- Semantic versioning: MAJOR.MINOR.PATCH
- Update version in scripts and documentation
- Create git tag: `v1.2.3`
- Generate changelog
- Create GitHub release with notes

## Questions?

- **Issues**: Use GitHub Issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for design questions
- **Chat**: See README.md for community links

## Resources

- [Linux Kernel Coding Style](https://www.kernel.org/doc/html/latest/process/coding-style.html)
- [Commit Message Guidelines](https://chris.beams.io/posts/git-commit/)
- [ShellCheck](https://www.shellcheck.net/)
- [DKMS Documentation](https://github.com/dell/dkms)
- [HID Subsystem Documentation](https://www.kernel.org/doc/html/latest/hid/)

---

Thank you for contributing to better T1 MacBook Pro support on Linux! 🎉
