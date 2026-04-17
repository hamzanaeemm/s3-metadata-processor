# Changelog

All notable changes to s3-metadata-processor project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-04-17

### Added
- **Structured Logging**: JSON-formatted logs in Lambda for better observability
- **Error Handling**: Per-record error isolation in Lambda batch processing
- **Security Hardening**: 
  - S3 versioning, encryption, and public access blocks
  - Lambda X-Ray tracing and Dead Letter Queue (DLQ)
  - IAM policy scope hardening
  - Removed hardcoded credentials from Dockerfile
- **Monitoring & Alarms**:
  - CloudWatch alarms for Lambda errors and throttles
  - CloudWatch alarms for DynamoDB performance
  - CloudWatch alarms for S3 bucket size
  - 30-day log retention
- **Infrastructure Improvements**:
  - DynamoDB TTL for automatic record cleanup (90 days)
  - DynamoDB Global Secondary Index for bucket queries
  - DynamoDB Point-in-Time Recovery (PITR)
  - Lambda timeout increased to 60 seconds, memory to 512MB
  - S3 access logging for audit trail
- **Code Quality**:
  - ESLint configuration for Node.js and CommonJS
  - Prettier configuration for consistent formatting
  - npm scripts for `lint`, `format`, and validation
- **Documentation**:
  - Comprehensive README with architecture, usage, and troubleshooting
  - CONTRIBUTING guide with code standards and workflow
  - CHANGELOG for version tracking
  - Environment file template (.env.example)
- **Developer Experience**:
  - Enhanced Makefile with colored output and help target
  - New `make logs-lambda` and `make logs-errors` commands
  - Portable build process (removed awsume dependency)
  - Better error messages and validation

### Changed
- **Lambda Handler**: Refactored for production-grade code quality
  - Better error handling with per-record isolation
  - Structured logging with timestamps and context
  - More aggressive file preview detection (text/*, application/json, application/xml)
  - Improved binary file handling
- **Node.js Runtime**: Upgraded recommendation from 18.x to 20.x (Terraform: nodejs20.x)
- **Module System**: Enforced CommonJS throughout (type: commonjs in package.json)
- **Makefile**: Complete rewrite for robustness, portability, and developer experience
- **S3 Bucket Naming**: Changed from static `s3-file-processor-lambda-bucket` to unique name with account ID and stage
- **DynamoDB Table Naming**: Added stage suffix for environment isolation

### Fixed
- **Security**: Removed AWS credentials passed as Docker build arguments
- **Dockerfile**: Removed unused environment variable injection
- **Package.json**: Removed unused dependencies (aws-sdk v2, aws-cdk-lib, express, dotenv)
- **Makefile**: Removed dependency on `awsume` tool for portable setup
- **Terraform**: Lambda function name no longer hardcoded (added stage suffix)

### Deprecated
- aws-sdk v2 (use AWS SDK v3 instead - already in Lambda runtime)

### Removed
- Docker credential passing via build arguments
- Unused npm dependencies
- awsume dependency in Makefile
- Commented-out code in CircleCI and IAM roles

## [0.1.1] - 2026-04-10

### Added
- Initial S3→Lambda→DynamoDB pipeline
- Basic Lambda handler with S3 metadata reading
- Terraform infrastructure for Lambda, S3, and DynamoDB
- CircleCI configuration (disabled as .circleci_OFF)
- Makefile for build automation
- Basic README documentation

### Known Issues
- Hardcoded AWS credentials in Dockerfile (fixed in 0.2.0)
- No error handling for batch failures
- Minimal logging
- No monitoring or alarms
- Limited security hardening

## [0.1.0] - 2026-04-01

### Added
- Project initialization
- Basic project structure

---

## Upgrading

### From 0.1.1 to 0.2.0

**Breaking Changes:** None - backwards compatible

**Recommended Actions:**
1. Run `npm install` to update dependencies
2. Deploy new Lambda version: `make build-lambda && STAGE=dev make tf-apply`
3. Verify Lambda logs: `make logs-lambda STAGE=dev`
4. Monitor CloudWatch alarms for any issues

**Migration:**
```bash
# Pull latest changes
git pull origin main

# Install new dependencies
npm install

# Deploy new version
STAGE=dev make build-lambda
STAGE=dev make tf-apply

# Verify deployment
STAGE=dev make logs-lambda
```

---

## Future Roadmap

### Planned for 0.3.0
- Unit tests for Lambda handler
- Integration tests with localstack
- Lambda performance benchmarking
- S3 lifecycle policies for cost optimization
- Multi-region deployment support

### Under Consideration
- Event filtering for specific file types
- Metadata enrichment with ML services
- S3 Select for large file optimization
- Scheduled cleanup of old records
- Custom metrics dashboard

---

## Versioning

This project uses Semantic Versioning:
- **MAJOR**: Incompatible API or infrastructure changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes, security patches

---

## Release Process

1. Update CHANGELOG.md with changes
2. Bump version in package.json
3. Create git tag: `git tag v0.2.0`
4. Push to repository: `git push origin main --tags`
5. Deploy to prod: `STAGE=prod make tf-apply`
6. Create GitHub release with changelog

---

For detailed information on specific changes, please refer to:
- [README.md](README.md) - Project overview and usage
- [CONTRIBUTING.md](CONTRIBUTING.md) - Development guidelines
- Git commit history for granular changes
