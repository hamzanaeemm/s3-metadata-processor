# Architecture Documentation

## System Overview

This document provides a comprehensive overview of the s3-metadata-processor infrastructure, including design decisions, component interactions, and deployment scenarios.

## Table of Contents
1. [System Architecture](#system-architecture)
2. [Component Design](#component-design)
3. [Data Flow](#data-flow)
4. [Deployment Architecture](#deployment-architecture)
5. [Security Architecture](#security-architecture)
6. [Scalability & Performance](#scalability--performance)
7. [Disaster Recovery](#disaster-recovery)
8. [Monitoring & Observability](#monitoring--observability)
9. [Cost Analysis](#cost-analysis)

---

## System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS Account                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────────┐                                                    │
│  │  S3 Bucket       │                                                    │
│  │  (Versioned)     │                                                    │
│  │  (Encrypted)     │                                                    │
│  │  (Logged)        │                                                    │
│  └────────┬─────────┘                                                    │
│           │                                                              │
│      ObjectCreated                                                       │
│      Event Notification                                                  │
│           │                                                              │
│           ▼                                                              │
│  ┌──────────────────────────────┐                                       │
│  │  Lambda Function             │                                       │
│  │  (Node.js 20.x)              │                                       │
│  │  (512MB, 60s timeout)        │                                       │
│  │  (X-Ray tracing)             │                                       │
│  │                              │                                       │
│  │  1. Read S3 metadata         │                                       │
│  │  2. Extract file preview     │                                       │
│  │  3. Store in DynamoDB       │                                       │
│  │  4. Log operations           │                                       │
│  └────────┬─────────────────────┘                                       │
│           │                                                              │
│           ├─────────────────────────────┐                               │
│           │                             │                               │
│           ▼                             ▼                               │
│  ┌──────────────────┐        ┌──────────────────┐                      │
│  │ DynamoDB Table   │        │ CloudWatch Logs  │                      │
│  │ (On-demand)      │        │ (30 day ret.)    │                      │
│  │ (TTL: 90 days)   │        │                  │                      │
│  │ (PITR enabled)   │        │ - Log streams    │                      │
│  │ (GSI enabled)    │        │ - Metrics        │                      │
│  └──────────────────┘        │ - Alarms         │                      │
│                              └──────────────────┘                      │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│ S3 Event Notification                                                    │
└──────────────────┬──────────────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Lambda Invocation                                                        │
│ • Sync: Event arrives within milliseconds                               │
│ • Retry: Auto-retry on throttle (max 2 retries)                        │
│ • DLQ: Failed invocations sent to SQS                                   │
└──────────────────┬──────────────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Lambda Handler Execution (src/lambda.cjs)                               │
│                                                                           │
│ 1. Validate environment (METADATA_TABLE_NAME)                            │
│ 2. Parse S3 event records                                               │
│ 3. For each record:                                                      │
│    a. HeadObject: Get metadata (size, type, tags, etc.)                 │
│    b. GetObject: Read file body (selective based on type)               │
│    c. Preview: Extract first KB of text/JSON/XML                        │
│    d. Store: Write to DynamoDB with metadata                            │
│    e. Log: Structured JSON logs to CloudWatch                           │
│ 4. Handle errors: Catch per-record, continue processing                │
│ 5. Return: Detailed response with successes/failures                    │
└──────────────────┬──────────────────────────────────────────────────────┘
                   │
                   ├─────────────────────────────┬──────────────────────────┐
                   │                             │                          │
                   ▼                             ▼                          ▼
        ┌─────────────────────┐    ┌──────────────────────┐   ┌──────────────────┐
        │ DynamoDB:           │    │ CloudWatch Logs:     │   │ X-Ray (Tracing): │
        │                     │    │                      │   │                  │
        │ object_id (PK)      │    │ - Processing time    │   │ - Performance    │
        │ processed_at (SK)   │    │ - Errors             │   │   metrics        │
        │ bucket              │    │ - Operation details  │   │ - Service map    │
        │ object_key          │    │ - Batch stats        │   │ - Latency        │
        │ content_type        │    │                      │   │                  │
        │ content_length      │    │ Retention: 30 days   │   │ Real-time view   │
        │ e_tag               │    │                      │   │ of execution      │
        │ last_modified       │    │                      │   │                  │
        │ user_metadata       │    │                      │   │                  │
        │ file_preview        │    │                      │   │                  │
        │ ttl_timestamp       │    │                      │   │                  │
        │                     │    │                      │   │                  │
        │ TTL: 90 days        │    │ Alarms:              │   │                  │
        │ Stream: IMAGES      │    │ - Lambda Errors      │   └──────────────────┘
        │ PITR: Enabled       │    │ - Lambda Throttles   │
        │ GSI: bucket+time    │    │ - DynamoDB Errors    │
        └─────────────────────┘    │                      │
                                   └──────────────────────┘
```

---

## Component Design

### 1. S3 Bucket

**Resource**: `aws_s3_bucket.file_upload_bucket`

**Characteristics**:
- Unique naming: `{bucket-name}-{account-id}-{stage}`
- Versioning enabled (data protection)
- Server-side encryption (AES256)
- Access logging to separate bucket
- Public access blocked
- CloudWatch alarm for size (>100GB)

**Access Pattern**:
- Lambda reads via S3:GetObject
- Lambda reads metadata via S3:GetObjectTagging
- S3 logs access to separate bucket

**Retention**:
- Versions: Indefinite (manual cleanup or lifecycle policies)
- Logs: 90 days retention (configurable)

### 2. Lambda Function

**Resource**: `aws_lambda_function.s3_file_processor_lambda`

**Configuration**:
```yaml
Runtime: nodejs20.x
Memory: 512 MB
Timeout: 60 seconds
Ephemeral Storage: 512 MB
Tracing: X-Ray Active
Handler: index.handler
```

**Handler Logic** (`src/lambda.cjs`):
```javascript
async handler(event) {
  // 1. Environment validation
  // 2. Event validation
  // 3. Batch processing with error isolation
  //    - Per-record try-catch
  //    - Continue on partial failures
  //    - Aggregate results
  // 4. Structured logging
  // 5. DynamoDB PutItem for each record
  // 6. Return 207 Multi-Status for partial success
}
```

**Performance Characteristics**:
- Cold start: ~1-2 seconds
- Warm start: ~200ms
- Average processing: 500-1000ms per file
- Memory: 256-512MB utilized
- Network: ~2-5ms per AWS service call

**Error Handling**:
- Record-level failures don't stop batch
- DLQ captures invocation failures
- CloudWatch alarm on errors
- Structured error logging

### 3. DynamoDB Table

**Resource**: `aws_dynamodb_table.s3_metadata_table`

**Schema**:
```
Partition Key: object_id (String)
Sort Key: processed_at (String)
Format: bucket#key as PK to enable queries by object

Example:
object_id: "my-bucket#folder/file.txt"
processed_at: "2026-04-17T10:30:45.123Z"
```

**Attributes**:
- `object_id`: Composite identifier (bucket#key)
- `processed_at`: ISO timestamp for sorting
- `bucket`: Bucket name for filtering
- `object_key`: Full S3 key path
- `content_type`: MIME type
- `content_length`: File size in bytes
- `e_tag`: S3 ETag for change detection
- `last_modified`: S3 LastModified timestamp
- `user_metadata`: JSON string of S3 user metadata
- `file_preview`: First 1KB of text content
- `ttl_timestamp`: Unix timestamp for TTL-based cleanup

**Indexes**:
- **Primary Index**: `(object_id, processed_at)`
  - Query by object_id (object lookup)
  - Range queries by processed_at (time range)

- **GSI**: `bucket-processed_at-index`
  - Query by bucket (find all objects in bucket)
  - Range queries by processed_at
  - Use case: "Find all metadata for this bucket after timestamp X"

**Billing Mode**: Pay-Per-Request
- No auto-scaling needed
- Cost scales linearly with usage
- ~$0.0006 per 1,000 write units
- Perfect for variable workloads

**Data Protection**:
- PITR: 35-day recovery window
- Streams: Enabled (NEW_AND_OLD_IMAGES)
- TTL: 90-day auto-deletion
- Backup: Can enable manual snapshots

### 4. CloudWatch Logs

**Log Group**: `/aws/lambda/s3-file-processor-lambda-{stage}`

**Retention**: 30 days

**Log Streams**:
- One stream per Lambda invocation
- Automatic creation by Lambda runtime
- Automatic deletion after retention expiry

**Log Format** (Structured JSON):
```json
{
  "level": "INFO",
  "message": "Processing S3 object",
  "bucket": "my-bucket",
  "key": "file.txt",
  "contentType": "text/plain",
  "contentLength": 1024,
  "recordIndex": 0,
  "timestamp": "2026-04-17T10:30:45.123Z"
}
```

**Alarms**:
- Lambda Errors: Sum > 0 per 5 min
- Lambda Throttles: Sum > 0 per 5 min
- DynamoDB Write Throttle: Sum > 0 per 5 min
- DynamoDB User Errors: Sum > 5 per 5 min
- S3 Bucket Size: Avg > 100 GB per day

### 5. Dead Letter Queue (SQS)

**Resource**: `aws_sqs_queue.lambda_dlq`

**Configuration**:
- Visibility timeout: 300 seconds (5 min)
- Message retention: 14 days
- Used for Lambda invocation failures
- Triggered on:
  - Lambda execution timeout
  - Lambda function errors (max retries exceeded)
  - Lambda throttling

**Use Cases**:
- Capture failed batches for replay
- Alert on infrastructure issues
- Manual investigation of failure modes

---

## Data Flow

### Request Flow (Happy Path)

```
1. User uploads file to S3
   └─▶ aws s3 cp myfile.txt s3://bucket-name/

2. S3 generates ObjectCreated event
   └─▶ Event contains bucket, key, timestamp, user identity

3. S3 invokes Lambda function
   └─▶ Synchronous invocation
   └─▶ Event passed as first argument
   └─▶ Lambda cold start (~1-2s) or warm start (~200ms)

4. Lambda handler parses S3 event
   └─▶ Extract bucket name
   └─▶ Extract object key (URL decode)
   └─▶ Validate required fields

5. Lambda calls S3 HeadObject
   └─▶ Get object metadata (async call)
   └─▶ Response includes: size, type, ETag, LastModified, etc.
   └─▶ Network latency: ~5ms + processing

6. Lambda calls S3 GetObject
   └─▶ Read object body (selective based on type)
   └─▶ For binary: Skip body, store "[binary]"
   └─▶ For text: Read full body (up to 512MB Lambda limit)
   └─▶ Network latency: ~10ms + data transfer

7. Lambda processes data
   └─▶ Extract file preview (first 1KB of text)
   └─▶ Format metadata record
   └─▶ Create DynamoDB item

8. Lambda calls DynamoDB PutItem
   └─▶ Write to metadata table
   └─▶ Async operation with auto-retry
   └─▶ Network latency: ~3-5ms

9. Lambda logs structured JSON
   └─▶ CloudWatch receives log stream
   └─▶ Logs persisted for 30 days
   └─▶ Pattern matching for alarms

10. Lambda returns response
    └─▶ HTTP 200 with metadata summary
    └─▶ Response logged to CloudWatch
    └─▶ X-Ray trace recorded
    └─▶ Execution completes

11. S3 confirms object stored
    └─▶ User receives success response
    └─▶ Total latency: 500-1500ms (S3 + Lambda)
```

### Error Flow

```
1. Lambda invocation fails
   └─▶ Runtime error, timeout, or out-of-memory
   └─▶ Lambda automatically retries (max 2 retries)
   └─▶ Last retry failure sent to SQS DLQ

2. Handler catches per-record error
   └─▶ Logs error with context
   └─▶ Continues processing other records
   └─▶ Returns 207 Multi-Status

3. Error handling paths:
   a) Authentication/Authorization
      └─▶ IAM denied → CloudWatch error → Alarm triggers
   
   b) S3 Object not found
      └─▶ Caught in GetObject call
      └─▶ Record logged as failed
      └─▶ Continue with next record
   
   c) DynamoDB write fails
      └─▶ Caught in PutItem call
      └─▶ Record logged as failed
      └─▶ Contributes to alarm threshold

4. CloudWatch alarm triggers
   └─▶ SNS notification (if configured)
   └─▶ PagerDuty alert (if integrated)
   └─▶ Team is notified

5. Operations review
   └─▶ Check CloudWatch Logs
   └─▶ Review DLQ messages
   └─▶ Manually replay if needed
```

---

## Deployment Architecture

### Environment Stages

| Stage | Account | Region | Purpose | Retention |
|-------|---------|--------|---------|-----------|
| **dev** | 743908177622 | eu-central-1 | Development/testing | 30 days logs, 90 days data |
| **test** | 754885218237 | eu-central-1 | Integration testing | 30 days logs, 90 days data |
| **prod** | 021088884718 | eu-central-1 | Production workload | 30 days logs, 90 days data |

### CI/CD Pipeline

```
Git Push
  │
  ▼
CircleCI Trigger
  │
  ├─▶ setup_workspace: Checkout code
  │
  ├─▶ code_quality (parallel)
  │    ├─ ESLint (npm run lint)
  │    ├─ Prettier (npm run format:check)
  │    └─ Terraform validate
  │
  ├─▶ build_lambda (requires code_quality passes)
  │    ├─ npm ci --omit=dev
  │    └─ make build-lambda
  │
  ├─▶ tf-plan-dev (requires build_lambda)
  │    └─ terraform plan with staged zip
  │
  ├─▶ tf-apply-dev (requires tf-plan-dev)
  │    └─ terraform apply
  │
  └─▶ Production requires manual approval
      ├─ tf-plan-prod
      ├─ Approval gate (manual click)
      └─ tf-apply-prod
```

### Local Development Flow

```
Developer makes changes
  │
  ├─ Lint: make lint
  │
  ├─ Format: make format
  │
  ├─ Validate: make validate
  │
  ├─ Build: make build-lambda
  │
  ├─ Deploy: STAGE=dev make tf-apply
  │
  ├─ Test: Upload file to S3
  │
  ├─ Verify: make logs-lambda STAGE=dev
  │
  └─ Cleanup: STAGE=dev make tf-delete
```

---

## Security Architecture

### Identity & Access Control

**Lambda Execution Role**:
```json
{
  "AssumeRole": {
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }
}
```

**Lambda Permissions** (Least Privilege):
```json
[
  {
    "Sid": "AllowCloudWatchLogs",
    "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
    "Resource": "arn:aws:logs:*:*:log-group:/aws/lambda/s3-file-processor-lambda*"
  },
  {
    "Sid": "AllowReadUploadedObjects",
    "Action": ["s3:GetObject", "s3:GetObjectTagging"],
    "Resource": "arn:aws:s3:::bucket-name/*"
  },
  {
    "Sid": "AllowWriteMetadataToDynamoDB",
    "Action": ["dynamodb:PutItem"],
    "Resource": "arn:aws:dynamodb:*:*:table/s3-file-metadata*"
  },
  {
    "Sid": "AllowXRayAccess",
    "Action": ["xray:PutTraceSegments", "xray:PutTelemetryRecords"],
    "Resource": "*"
  }
]
```

### Data Protection

| Layer | Method | Details |
|-------|--------|---------|
| **Transport** | HTTPS/TLS | All AWS API calls use TLS 1.2+ |
| **S3 Storage** | AES256 | Server-side encryption, AWS-managed keys |
| **S3 Access** | Logging | All access logged to separate bucket |
| **DynamoDB** | Encryption | AWS-managed encryption at rest |
| **DynamoDB** | PITR | 35-day recovery window |
| **Secrets** | No hardcoding | Lambda uses IAM role, no credentials |
| **Logs** | Structured JSON | No sensitive data in logs |

### Network Security

- **S3 Public Access**: Blocked on all buckets
- **Lambda Execution**: VPC not required (serverless)
- **DynamoDB Access**: IAM-gated only
- **CloudWatch Logs**: IAM-gated only

### Compliance

- **Audit Trail**: CloudTrail captures all API calls
- **Data Retention**: Automatic cleanup via TTL
- **Encryption**: In transit (TLS) and at rest (AES256)
- **Least Privilege**: Minimal IAM permissions

---

## Scalability & Performance

### Horizontal Scaling

**S3 Event Distribution**:
- S3 can deliver thousands of events/second
- Each event invokes separate Lambda instance
- Lambda scales automatically (no config needed)
- Concurrent execution limit: 1000 (default, AWS supports increase)

**Lambda Concurrency**:
- Reserved Concurrency: Can be set per function
- Unreserved Concurrency: Shared pool, burst to 1000
- Throttling: New invocations rejected after limit
- DLQ: Captured for retry later

**DynamoDB Scaling**:
- On-demand billing scales automatically
- No capacity planning needed
- Throttling possible under extreme load
- CloudWatch alarms help identify limits

### Vertical Scaling

| Resource | Current | Min | Max | Notes |
|----------|---------|-----|-----|-------|
| **Lambda Memory** | 512 MB | 128 MB | 10,240 MB | More memory = faster CPU |
| **Lambda Timeout** | 60s | 1s | 900s | Should be < 15min |
| **Lambda Storage** | 512 MB | 512 MB | 10,240 MB | For temp files/logs |
| **File Preview** | 1 KB | 256 B | 100 KB | For text extraction |

### Performance Optimization

**Lambda**:
```javascript
// Reuse SDK clients (outside handler)
const s3 = new S3Client({});
const dynamodb = new DynamoDBClient({});

// Async/await for better performance
// Batch operations where possible
// Structured logging with relevant context
```

**S3**:
- Versioning: Slight overhead, worth it for safety
- Encryption: Minimal overhead, recommended
- Logging: Separate bucket prevents recursion

**DynamoDB**:
- On-demand: No tuning needed, auto-scales
- GSI: Minimal overhead, enables queries
- TTL: Background process, no performance impact

### Latency Analysis

| Component | Min | Avg | Max | Notes |
|-----------|-----|-----|-----|-------|
| **S3 Event** | 10ms | 50ms | 100ms | Time to deliver event to Lambda |
| **Lambda Cold Start** | 1s | 1.5s | 2s | First invocation after 15 min idle |
| **Lambda Warm Start** | 100ms | 200ms | 300ms | Subsequent invocations |
| **S3 HeadObject** | 3ms | 5ms | 10ms | Metadata fetch |
| **S3 GetObject** | 5ms | 15ms | 50ms | Body fetch + transfer |
| **DynamoDB PutItem** | 3ms | 5ms | 15ms | Write to table |
| **Handler Processing** | 50ms | 200ms | 1000ms | Parsing, logic |
| **End-to-End** | 200ms | 500ms | 1500ms | S3 event to Lambda completion |

---

## Disaster Recovery

### RTO/RPO

| Scenario | RTO | RPO | Recovery |
|----------|-----|-----|----------|
| **Lambda Code Update** | 1s | 0s | Rollback to previous version |
| **DynamoDB Data Loss** | 5-10min | 35 days | PITR restore to point-in-time |
| **S3 Data Corruption** | 1-2min | Versioning window | Restore from S3 version history |
| **Regional Outage** | 1-4 hours | 0s | Deploy to another region |
| **Account Compromise** | 30min | 0s | Access control restore |

### Backup Strategy

**S3**:
- Versioning: All versions retained indefinitely
- Cross-region replication: Optional (not configured)
- Manual snapshots: Via AWS Backup service

**DynamoDB**:
- Point-in-time recovery: 35-day window
- Manual exports: Can export to S3
- AWS Backup: Optional for compliance

**Lambda**:
- Code: Stored in Git repository
- Versions: Published versions tracked
- Rollback: Can update to previous version instantly

### Incident Response

1. **Detection**: CloudWatch alarms trigger
2. **Alert**: SNS notification (if configured)
3. **Investigation**: CloudWatch Logs, X-Ray, DLQ
4. **Mitigation**:
   - Manual invocation fixes
   - DLQ message replay
   - Lambda version rollback
5. **Resolution**: Deploy fix, validate
6. **Post-Mortem**: Analyze logs, improve

---

## Monitoring & Observability

### Metrics

**Lambda Metrics** (CloudWatch):
```
Invocations:    Total number of times Lambda was invoked
Errors:         Number of execution failures
Throttles:      Number of times concurrency limit was hit
Duration:       Execution time in milliseconds
ConcurrentExecutions: Current concurrent invocation count
```

**DynamoDB Metrics**:
```
ConsumedWriteCapacityUnits: Write throughput consumed
UserErrors: Client-side errors (validation, etc.)
SystemErrors: Server-side errors
SuccessfulRequestLatency: P99 latency for successful requests
```

**S3 Metrics**:
```
BucketSizeBytes: Total storage size
NumberOfObjects: Current object count
AllRequests: Total API calls
4xxErrors: Client errors (AccessDenied, etc.)
5xxErrors: Server errors
```

### Logs

**CloudWatch Logs**:
- Automatic creation by Lambda runtime
- Structured JSON format for parsing
- 30-day retention
- Real-time streaming capability
- Log Insights queries for analysis

**Log Queries**:
```
# Find errors
{ ($.level = "ERROR") }

# Find slow requests
{ ($.duration > 1000) }

# Aggregate by bucket
stats count(*) as request_count by bucket
```

### X-Ray Tracing

**Traces Captured**:
- Lambda execution start/end
- AWS SDK calls (S3, DynamoDB)
- Subsegment timing for each call
- Errors and exceptions

**Service Map**:
```
Client
  │
  ├─ Lambda (100ms avg)
  │   ├─ S3 HeadObject (5ms)
  │   ├─ S3 GetObject (15ms)
  │   └─ DynamoDB PutItem (5ms)
  │
  └─ Returns (200 OK)
```

---

## Cost Analysis

### Pricing Model (AWS Pricing as of Q1 2026, eu-central-1)

| Service | Metric | Price | Notes |
|---------|--------|-------|-------|
| **Lambda** | Per 1M requests | $0.20 | First 1M/month free |
| **Lambda** | Per 1GB-second | $0.0000166667 | 512MB for 1000ms = 0.5 GB-sec |
| **S3 PUT** | Per 1K requests | $0.005 | Standard storage class |
| **S3 Storage** | Per GB-month | $0.024 | Standard storage class |
| **DynamoDB** | Per 1M writes | $1.25 | On-demand mode |
| **DynamoDB** | Per 1M reads | $0.25 | (Not used in this arcuitecture) |
| **DynamoDB** | Storage | $0.25/GB-month | With auto-cleanup via TTL |
| **CloudWatch Logs** | Per GB ingested | $0.50 | 30-day retention |

### Example Costs (10,000 uploads/month)

```
Lambda Invocations (10,000):
  ├─ Requests: 10,000 @ $0.20/1M = $0.002
  └─ Compute: 10,000 * 0.5GB-sec @ $0.0000166667 = $0.083
              (500ms average execution time)
  Total: $0.085

S3 Operations:
  └─ PUT requests: 10,000 @ $0.005/1K = $0.050
  Total: $0.050

S3 Storage:
  └─ Assume 100GB stored for month
  └─ Cost: 100GB @ $0.024 = $2.40

DynamoDB:
  ├─ Write units: 10,000 @ $1.25/1M = $0.0125
  └─ Storage: 10,000 * 50KB = 500GB first week
            → Auto-cleanup after 90 days
            → Assume 5GB avg storage
            → Cost: 5GB @ $0.25 = $1.25
  Total: $1.2625

CloudWatch Logs:
  └─ ~50KB per invocation * 10,000 = 500GB
  └─ Cost: 500GB @ $0.50 = $250.00

Total Monthly Cost: ~$253.80
Cost Per Upload: ~$0.0254
```

### Cost Optimization Tips

1. **Reduce file preview size**: From 1KB to 100B = 10x savings on log size
2. **Implement log filtering**: Only log errors/metrics, not every invocation
3. **Use lifecycle policies**: Archive old S3 objects to Glacier
4. **Enable S3 Select**: Query specific fields instead of full object
5. **Batch DynamoDB writes**: Use BatchWriteItem for multiple records
6. **Consider reserved capacity**: If workload is predictable

### Cost for Different Volumes

| Uploads/Month | Lambda | S3 | DynamoDB | CloudWatch | Total |
|---------------|--------|-----|----------|-----------|-------|
| **100** | $0.01 | $0.01 | $0.02 | $2.50 | $2.54 |
| **1,000** | $0.01 | $0.01 | $0.02 | $25.00 | $25.04 |
| **10,000** | $0.08 | $0.05 | $1.26 | $250.00 | $251.39 |
| **100,000** | $0.82 | $0.50 | $12.60 | $2,500.00 | $2,513.92 |
| **1,000,000** | $8.33 | $5.00 | $126.00 | $25,000.00 | $25,139.33 |

---

## Decision Log

### Design Decisions

1. **On-Demand DynamoDB Billing**
   - Rationale: No capacity planning, auto-scales
   - Alternative: Provisioned capacity (cheaper at scale)
   - Decision: On-demand for operational simplicity, cost acceptable for < 1M/month

2. **Node.js 20.x Runtime**
   - Rationale: Latest LTS, better performance, built-in AWS SDK v3
   - Alternative: Node.js 18.x (older but stable)
   - Decision: 20.x for better performance and security

3. **50MB Lambda Memory (512MB allocated)**
   - Rationale: ~500MB actual usage for metadata extraction
   - Alternative: 256MB (slower), 1GB (overkill)
   - Decision: 512MB balances cost and performance

4. **60s Lambda Timeout**
   - Rationale: Sufficient for metadata extractions, S3 limits transfer time
   - Alternative: 30s (too aggressive), 120s (wasteful)
   - Decision: 60s provides safety margin

5. **S3 Versioning Enabled**
   - Rationale: Data protection, undo capability, minimal cost
   - Alternative: No versioning (saves storage)
   - Decision: Versioning enabled for safety

6. **DynamoDB TTL at 90 Days**
   - Rationale: Balance retention and storage costs
   - Alternative: 30 days (less history), 180 days (more cost)
   - Decision: 90 days matches typical compliance windows

7. **Structured JSON Logging**
   - Rationale: Enables Log Insights queries, metrics extraction
   - Alternative: Free-form text (easier to write, harder to parse)
   - Decision: Structured logging for production visibility

---

## Future Enhancements

1. **Multi-Region Replication**: S3 cross-region replication for DR
2. **S3 Event Filtering**: Filter events by prefix/suffix
3. **Lambda Concurrency Control**: Reserved concurrency for fairness
4. **Cost Optimization**: Implement log sampling, archive old records
5. **Advanced Monitoring**: Custom metrics dashboard, anomaly detection
6. **Integration**: SNS notifications, SQS integration, EventBridge rules

---

**Document Version**: 1.0  
**Last Updated**: April 17, 2026  
**Maintained By**: Platform Team
