resource "aws_s3_bucket" "file_upload_bucket" {
  bucket = "${var.s3_bucket_name}-${var.account_id}-${var.stage}"

  tags = {
    name         = var.s3_bucket_name
    terraform    = "true"
    ts-component = "s3-metadata-processor"
    ts-project   = "s3-metadata-processor"
    ts-stage     = var.stage
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "file_upload_bucket_pab" {
  bucket = aws_s3_bucket.file_upload_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "file_upload_versioning" {
  bucket = aws_s3_bucket.file_upload_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "file_upload_encryption" {
  bucket = aws_s3_bucket.file_upload_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable access logging
resource "aws_s3_bucket_logging" "file_upload_logging" {
  bucket = aws_s3_bucket.file_upload_bucket.id

  target_bucket = aws_s3_bucket.logs_bucket.id
  target_prefix = "file-uploads/"
}

# Logs bucket for S3 access logs
resource "aws_s3_bucket" "logs_bucket" {
  bucket = "${var.s3_bucket_name}-logs-${var.account_id}-${var.stage}"

  tags = {
    name         = "${var.s3_bucket_name}-logs"
    terraform    = "true"
    project      = var.project_name
    stage        = var.stage
  }
}

resource "aws_s3_bucket_public_access_block" "logs_bucket_pab" {
  bucket = aws_s3_bucket.logs_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lambda permission for S3 invocation
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_file_processor_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.file_upload_bucket.arn
}

# S3 bucket notification
resource "aws_s3_bucket_notification" "file_upload_notification" {
  bucket = aws_s3_bucket.file_upload_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_file_processor_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# CloudWatch alarm for S3 bucket size
resource "aws_cloudwatch_metric_alarm" "s3_bucket_size" {
  alarm_name          = "s3-file-processor-bucket-size-${var.stage}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400" # 1 day
  statistic           = "Average"
  threshold           = "107374182400" # 100 GB warning threshold
  alarm_description   = "Alert when S3 bucket exceeds 100 GB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName  = aws_s3_bucket.file_upload_bucket.id
    StorageType = "StandardStorage"
  }
}
