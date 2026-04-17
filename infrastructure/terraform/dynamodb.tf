resource "aws_dynamodb_table" "s3_metadata_table" {
  name         = "${var.metadata_table_name}-${var.stage}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "object_id"
  range_key    = "processed_at"

  attribute {
    name = "object_id"
    type = "S"
  }

  attribute {
    name = "processed_at"
    type = "S"
  }

  attribute {
    name = "bucket"
    type = "S"
  }

  # Global Secondary Index for querying by bucket
  global_secondary_index {
    name            = "bucket-processed_at-index"
    hash_key        = "bucket"
    range_key       = "processed_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "ttl_timestamp"
    enabled        = true
  }

  tags = {
    name         = var.metadata_table_name
    terraform    = "true"
    project      = var.project_name
    stage        = var.stage
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_write_throttle" {
  alarm_name          = "s3-metadata-table-write-throttle-${var.stage}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when DynamoDB table write is throttled"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.s3_metadata_table.name
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_user_errors" {
  alarm_name          = "s3-metadata-table-user-errors-${var.stage}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when DynamoDB user errors exceed threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.s3_metadata_table.name
  }
}
