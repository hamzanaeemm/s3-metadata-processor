# Contributing Guide

## Table of Contents
- [Development Setup](#development-setup)
- [Code Standards](#code-standards)
- [Commit Guidelines](#commit-guidelines)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)

## Development Setup

### Prerequisites
- Node.js 18+
- Terraform ≥1.9
- AWS CLI configured
- Make (for macOS/Linux)

### Initial Setup

```bash
# Clone the repository
git clone <repository-url>
cd s3-metadata-processor

# Install dependencies
npm install

# Verify setup
make validate
```

### Environment Variables

Create a `.env` file based on `.env.example`:

```bash
cp .env.example .env
# Edit .env with your values
```

## Code Standards

### JavaScript/Node.js

All code must follow the configured ESLint and Prettier rules.

**Before committing:**

```bash
# Check code style
make lint

# Auto-fix formatting
make format

# Verify no errors
make format-check
```

**Key Standards:**
- Use `const` and `let` (never `var`)
- Always use strict equality (`===`, `!==`)
- Handle errors explicitly
- Use meaningful variable names
- Keep functions small and focused
- Add JSDoc comments for complex logic

### Lambda Handler (`src/lambda.cjs`)

**Guidelines:**
- ✅ Error handling for each record independently
- ✅ Structured JSON logging
- ✅ Security: Never log sensitive data
- ✅ Performance: Optimize AWS SDK calls
- ✅ Resilience: Graceful degradation on failures

Example pattern:
```javascript
try {
  // Implementation
} catch (error) {
  logger.error("Operation failed", error, { context: "data" });
  // Handle gracefully
}
```

### Terraform (`infrastructure/terraform/*.tf`)

**Guidelines:**
- Use meaningful resource names with stage suffix
- Include SID (Statement ID) for IAM policy statements
- Always tag resources (name, terraform, ts-component, ts-project, ts-stage)
- Use variables for configurability
- Add descriptions to important resources

Validate before committing:
```bash
make validate
```

Format files:
```bash
cd infrastructure/terraform
terraform fmt -recursive .
cd ../../..
```

## Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Adding/updating tests
- `chore`: Build, dependencies, tooling
- `ci`: CI/CD configuration

**Examples:**

```
feat(lambda): add retry logic for S3 operations

- Implement exponential backoff
- Add configurable retry count
- Log retry attempts

Closes #42
```

```
fix(terraform): correct IAM policy resource ARN

The Lambda execution role was missing permissions to write to DynamoDB.

Fixes #38
```

**Guidelines:**
- Write in imperative mood ("add" not "added")
- Don't capitalize the subject
- Keep subject under 50 characters
- Wrap body at 72 characters
- Reference issues and PRs when applicable

## Testing

### Manual Testing

Before submitting a PR, test in the dev environment:

```bash
# Deploy changes
STAGE=dev make tf-apply

# Upload a test file
aws s3 cp test.txt "s3://<bucket-name>/test.txt"

# Check Lambda logs
make logs-lambda STAGE=dev

# Verify DynamoDB records
aws dynamodb scan --table-name s3-file-metadata-dev

# Clean up test environment
STAGE=dev make tf-delete
```

### Code Quality Checks

```bash
# Run linter
make lint

# Format check (non-destructive)
make format-check

# Validate Terraform
make validate

# All at once
make lint && make format-check && make validate
```

## Pull Request Process

### Before Creating a PR

1. **Update your branch from main**
   ```bash
   git checkout main
   git pull origin main
   git checkout your-feature-branch
   git rebase main
   ```

2. **Run all quality checks**
   ```bash
   make lint
   make format
   make validate
   ```

3. **Test your changes**
   ```bash
   STAGE=dev make tf-apply
   # Test functionality
   STAGE=dev make tf-delete
   ```

4. **Commit**
   ```bash
   git add .
   git commit -m "feat(component): descriptive message"
   ```

### PR Description Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Infrastructure improvement
- [ ] Documentation
- [ ] Refactoring

## Testing Done
- [ ] Unit tested
- [ ] Manual tested in dev environment
- [ ] Tested with multiple file types (if applicable)

## Infrastructure Changes
- [ ] Terraform plan passed
- [ ] No breaking changes
- [ ] Backwards compatible

## Checklist
- [ ] Code follows style guidelines (make lint)
- [ ] Code formatted correctly (make format)
- [ ] Terraform validated (make validate)
- [ ] Documentation updated
- [ ] Commit messages follow guidelines
- [ ] No secrets or credentials in code

## Related Issues
Closes #<issue-number>
```

### Review Process

**Reviewers will check:**
- Code quality and style compliance
- Security implications
- Performance impact
- Documentation accuracy
- Terraform plan for resource changes

**Approval Requirements:**
- ✅ All CI checks passing
- ✅ At least 1 approval from team
- ✅ No merge conflicts
- ✅ Updated CHANGELOG.md (if applicable)

### Merging

After approval, merge to main:

```bash
# Update from main
git checkout main
git pull origin main

# Merge your branch
git merge --squash your-feature-branch

# Push to main
git push origin main
```

## Troubleshooting

### ESLint Failures

If ESLint fails:

```bash
# Auto-fix common issues
make lint:fix

# Review remaining issues manually
make lint
```

### Terraform Validation Fails

```bash
# Format files
cd infrastructure/terraform
terraform fmt -recursive .
cd ../../..

# Re-validate
make validate
```

### Lambda Deploy Fails

Check credentials and permissions:

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check CloudWatch logs
make logs-lambda STAGE=dev
```

## Getting Help

- Review the [README.md](README.md) for overview
- Check [GitHub Issues](issues) for known problems
- Ask in team Slack channel
- Create a detailed issue with:
  - What you tried
  - What you expected
  - What happened instead
  - Error messages/logs

## Code Review Etiquette

**As a Reviewer:**
- Be constructive and respectful
- Explain the reasoning behind feedback
- Acknowledge good work
- Suggest improvements, don't demand

**As an Author:**
- Accept feedback gracefully
- Ask for clarification if needed
- Update code based on feedback
- Re-request review when ready

## License

Contributing to this project means you agree to the project's license terms.

---

Thank you for contributing! 🚀
