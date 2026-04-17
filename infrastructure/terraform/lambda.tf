data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name               = "s3-file-processor-lambda-execution-role-${var.stage}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    name         = "s3-file-processor-lambda-execution-role"
    terraform    = "true"
    ts-component = "s3-metadata-processor"
  }
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/s3-file-processor-lambda*",
    ]
  }

  statement {
    sid    = "AllowReadUploadedObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
    ]
    resources = [
      "${aws_s3_bucket.file_upload_bucket.arn}/*",
    ]
  }

  statement {
    sid    = "AllowWriteMetadataToDynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
    ]
    resources = [
      aws_dynamodb_table.s3_metadata_table.arn,
    ]
  }

  statement {
    sid    = "AllowSendMessageToDLQ"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
    ]
    resources = [
      aws_sqs_queue.lambda_dlq.arn,
    ]
  }

  statement {
    sid    = "AllowXRayAccess"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = [
      "*",
    ]
  }
}

resource "aws_iam_role_policy" "lambda_execution_policy" {
  name   = "s3-file-processor-lambda-policy-${var.stage}"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_lambda_function" "s3_file_processor_lambda" {
  function_name = "s3-file-processor-lambda-${var.stage}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  filename         = "${path.module}/lambda/s3-file-processor-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/s3-file-processor-lambda.zip")

  timeout     = 60  # 1 minute - sufficient for reading and storing metadata
  memory_size = 512 # 512MB for efficient S3 operations
  ephemeral_storage {
    size = 512 # 512MB ephemeral storage (10240 max)
  }

  environment {
    variables = {
      METADATA_TABLE_NAME = aws_dynamodb_table.s3_metadata_table.name
      LOG_LEVEL           = "INFO"
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    name         = "s3-file-processor-lambda"
    terraform    = "true"
    ts-component = "s3-metadata-processor"
    ts-project   = "s3-metadata-processor"
    ts-stage     = var.stage
  }

  depends_on = [aws_iam_role_policy.lambda_execution_policy]
}

# Dead Letter Queue for failed Lambda invocations
resource "aws_sqs_queue" "lambda_dlq" {
  name                       = "s3-file-processor-lambda-dlq-${var.stage}"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300

  tags = {
    name         = "s3-file-processor-lambda-dlq"
    terraform    = "true"
    ts-component = "s3-metadata-processor"
    ts-project   = "s3-metadata-processor"
    ts-stage     = var.stage
  }
}

# CloudWatch Log Group with retention
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/s3-file-processor-lambda-${var.stage}"
  retention_in_days = 30

  tags = {
    name         = "s3-file-processor-lambda-logs"
    terraform    = "true"
    project      = var.project_name
    stage        = var.stage
  }
}

# CloudWatch Alarms for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "s3-file-processor-lambda-errors-${var.stage}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when Lambda function has errors"

  dimensions = {
    FunctionName = aws_lambda_function.s3_file_processor_lambda.function_name
  }

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "s3-file-processor-lambda-throttles-${var.stage}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when Lambda function is throttled"

  dimensions = {
    FunctionName = aws_lambda_function.s3_file_processor_lambda.function_name
  }

  treat_missing_data = "notBreaching"
}
