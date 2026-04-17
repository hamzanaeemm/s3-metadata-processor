# s3-metadata-processor

Production-grade AWS infrastructure for testing S3-to-Lambda-to-DynamoDB file metadata processing pipeline.

## Overview

This project implements a serverless architecture that:
- Listens for S3 object uploads
- Extracts metadata and file previews
- Stores metadata in DynamoDB
- Provides comprehensive logging and monitoring

### Architecture

```
┌─────────────┐       S3:ObjectCreated       ┌──────────────┐      DynamoDB
│   S3 Bucket │─────────────────────────────▶│ Lambda       │─────────────────▶┌─────────────────┐
│ (Versioned) │      Event Notification      │ (Node.js 20) │    PutItem       │ Metadata Table  │
└─────────────┘                               │              │                   └─────────────────┘
                                              └──────────────▘
                                                    │
                                                    ▼
                                            ┌──────────────────┐
                                            │ CloudWatch Logs  │
                                            │ (30-day storage) │
                                            └──────────────────┘
```

## Quick Start

### Prerequisites
- Node.js 18+ (20+ recommended)
- Terraform ≥1.9
- AWS CLI configured with appropriate credentials
- macOS, Linux, or WSL

### Installation

```bash
# Clone repository
git clone <repository>
cd s3-metadata-processor

# Install dependencies
npm install
```

### First Deployment

```bash
# Validate infrastructure code
make validate

# Build Lambda function
make build-lambda

# Deploy to dev environment
STAGE=dev make tf
```

## Configuration

### Environment Variables

**Lambda Environment Variables** (set in Terraform):
- `METADATA_TABLE_NAME`: DynamoDB table name for metadata storage
- `LOG_LEVEL`: CloudWatch log level (default: INFO)
- `AWS_REGION`: AWS region (auto-set by Lambda runtime)

**Make Variables**:
- `STAGE`: Deployment stage - `dev`, `test`, or `prod` (default: dev)
- `AWS_REGION`: AWS region for API calls (default: eu-central-1)

### Terraform Variables

Edit `infrastructure/terraform/dev.tfvars`, `test.tfvars`, or `prod.tfvars`:

```hcl
region              = "eu-central-1"
account_id          = "YOUR_ACCOUNT_ID"
stage               = "dev"
s3_bucket_name      = "s3-file-processor-lambda-bucket"
metadata_table_name = "s3-file-metadata"
```

## Usage

### Make Targets

```bash
# Display all available targets
make help

# Code Quality
make lint              # Run ESLint
make format            # Format code with Prettier
make validate          # Validate Terraform

# Infrastructure
make tf-init           # Initialize Terraform
make tf-plan           # Plan changes
make tf-apply          # Apply changes
make tf-delete         # Destroy resources (⚠️ DESTRUCTIVE)

# Development
make build-lambda      # Build Lambda package
make logs-lambda       # Tail Lambda logs
make logs-errors       # Show Lambda errors
make clean             # Remove build artifacts
```

### Lambda Handler Best Practices

The Lambda handler (`src/lambda.cjs`) includes:

✅ **Error Handling**: Per-record error isolation with graceful degradation  
✅ **Structured Logging**: JSON-formatted logs with timestamps  
✅ **Security**: Strict IAM permissions, no credentials in code  
✅ **Performance**: Optimized file reading, configurable preview limits  
✅ **Observability**: CloudWatch metrics, alarms, and DLQ setup  
✅ **Resilience**: Timeout/memory configuration, X-Ray tracing  

## Infrastructure as Code

### Terraform Components

| Component | Stage | Features |
|-----------|-------|----------|
| **S3 Bucket** | ✓ | Versioning, encryption, logging, access blocks, size monitoring |
| **Lambda** | ✓ | 512MB memory, 60s timeout, X-Ray tracing, DLQ, structured logging |
| **DynamoDB** | ✓ | On-demand billing, GSI, TTL, PITR, stream view type |
| **Monitoring** | ✓ | CloudWatch alarms for errors, throttles, metrics |
| **IAM** | ✓ | Least-privilege policies, resource-specific permissions |

### Security Features

- **S3**: Versioning, encryption, public access blocks, access logging
- **Lambda**: X-Ray tracing, restricted IAM policies, error catching
- **DynamoDB**: Point-in-time recovery, TTL, stream configuration
- **Networking**: Least-privilege IAM, no hardcoded credentials

### Cost Optimization

- **DynamoDB**: On-demand billing (pay-per-request)
- **S3**: Standard storage with lifecycle policies possible
- **Lambda**: Memory-optimized (512MB for typical metadata)
- **Monitoring**: Metric alarms help identify runaway costs

**Estimated Cost (per 1,000 uploads):**
- Lambda: ~$0.0002
- S3: ~$0.005
- DynamoDB: ~$0.0006
- Total: ~$0.0008 per upload

## Monitoring & Observability

### CloudWatch Logs

Real-time lambda logs with automated retention:

```bash
# View logs
make logs-lambda STAGE=dev

# Find errors
make logs-errors STAGE=dev

# Manual query
aws logs tail /aws/lambda/s3-file-processor-lambda-dev --follow
```

### CloudWatch Alarms

Automatically configured for:
- Lambda function errors
- Lambda throttling events
- DynamoDB write throttles
- DynamoDB user errors
- S3 bucket size exceeding 100 GB

View in AWS Console → CloudWatch → Alarms

### Log Format

Lambda uses structured JSON logging:

```json
{
  "level": "INFO",
  "message": "Processing S3 object",
  "bucket": "my-bucket",
  "key": "path/to/file.txt",
  "timestamp": "2026-04-17T10:30:45.123Z"
}
```

## Useful Links

- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)

## Support

For issues, questions, or feature requests:
1. Check existing GitHub issues
2. Review CloudWatch logs: `make logs-lambda`
3. Validate infrastructure: `make validate`
4. Create a GitHub issue with detailed description

## License

[Add your license here]

---

**Last Updated**: April 2026  
**Version**: 0.2.0  
**Maintained By**: Your Team

