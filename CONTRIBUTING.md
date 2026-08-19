# Contributing to Proxmox Infrastructure

Thank you for your interest in contributing! This project is a portfolio
demonstration of infrastructure-as-code best practices using Terraform and
Ansible for Proxmox homelab management. While it's primarily a personal
project, I welcome contributions that improve documentation, fix bugs, or
enhance the overall quality.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Contribution Workflow](#contribution-workflow)
- [Style Guidelines](#style-guidelines)
- [Commit Message Conventions](#commit-message-conventions)

## Code of Conduct

This project follows a simple principle: **Be respectful and constructive**.
We're all here to learn and improve.

## How Can I Contribute?

### Reporting Issues

If you find a bug, documentation error, or have a suggestion:

1. **Check existing issues** to avoid duplicates
2. **Create a new issue** with:
   - Clear, descriptive title
   - Detailed description of the problem or suggestion
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Environment details (if applicable)

### Suggesting Enhancements

Enhancement suggestions are welcome! Please provide:

- **Use case**: Why this enhancement would be useful
- **Proposed solution**: How you envision it working
- **Alternatives**: Any alternative approaches you've considered

### Pull Requests

I welcome pull requests for:

- Documentation improvements
- Bug fixes
- Ansible role enhancements
- Terraform module improvements
- CI/CD improvements

## Development Setup

### Prerequisites

- Terraform >= 1.5.0
- Ansible >= 2.15
- `ansible-lint`
- `yamllint`
- `markdownlint-cli2`
- `shellcheck`
- `pre-commit`
- Python 3.x (for dynamic inventory scripts)

### Local Environment

```bash
# Clone the repository
git clone <repo-url>
cd proxmox-infra

# Install pre-commit hooks
cd ansible && make setup

# Install Ansible Galaxy collections
cd ansible && make update-roles

# Validate Ansible playbooks
cd ansible && make lint

# Initialize Terraform
cd terraform/lxc && make init
```

## Contribution Workflow

1. **Fork the repository**

2. **Create a feature branch**

   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing patterns and conventions
   - Update documentation if needed
   - Test your changes locally

4. **Validate your changes**

   ```bash
   # Lint Ansible playbooks
   cd ansible && make lint

   # Format Terraform
   cd terraform/<project> && terraform fmt -recursive

   # Validate Terraform
   cd terraform/<project> && make plan
   ```

5. **Commit with meaningful messages** (see [Commit
   Conventions](#commit-message-conventions))

6. **Push to your fork**

   ```bash
   git push origin feature/your-feature-name
   ```

7. **Open a Pull Request**
   - Reference any related issues
   - Describe what changed and why
   - Include plan output for Terraform changes

## Style Guidelines

### Terraform

- Use `terraform fmt` for consistent formatting
- Pin provider versions in `versions.tf`
- Use variables with descriptions and type constraints
- Use locals for computed values
- Follow the module structure in each project directory

### Ansible

- Follow idempotent design principles
- Use `ansible-lint` with the production profile
- Organize with roles for reusable configurations
- Use `group_vars` and `host_vars` for environment-specific configs
- Encrypt sensitive data with Ansible Vault
- Use tags for flexible task execution

### Shell Scripts

- Use `shellcheck` for validation
- Write modular scripts with functions
- Include comments for each major section
- Validate all inputs
- Use `trap` for error handling and cleanup

### Documentation

- Use Markdown for all documentation
- Include code examples where helpful
- Update the main README if adding significant features
- Keep line length reasonable (~80 characters max)
- Use proper headings hierarchy

## Commit Message Conventions

Follow conventional commit format:

```text
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `chore`: Maintenance tasks
- `test`: Testing improvements
- `ci`: CI/CD changes
- `build`: Build system changes

### Examples

```text
feat(ansible): add Docker role for LXC containers

- Create role for Docker CE installation
- Add handler for Docker service restart
- Support configurable storage driver
```

```text
fix(terraform): correct LXC memory allocation

The memory parameter was set in bytes instead of MB,
causing OOM kills on container startup.
```

```text
chore(ansible): update Galaxy collection versions

Bump kubernetes.core to 6.2.0 and community.general
to 12.1.0 for compatibility with Ansible 2.17.
```

## Testing Requirements

Before submitting a PR:

1. **Lint Ansible playbooks**

   ```bash
   cd ansible && make lint
   ```

2. **Validate Terraform**

   ```bash
   cd terraform/<project> && make plan
   ```

3. **Check shell scripts**

   ```bash
   shellcheck scripts/*.sh
   ```

4. **Update documentation** if you changed:
   - Role variables
   - Terraform variables
   - Infrastructure architecture
   - Prerequisites

## License

By contributing, you agree that your contributions will be licensed under the
MIT License.
