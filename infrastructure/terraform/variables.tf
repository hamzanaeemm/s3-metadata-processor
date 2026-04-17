variable "region" {
  description = "AWS region"
  type        = string
}

variable "stage" {
  description = "Stage of the Account"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "s3_bucket_name" {
  description = "name of the s3 bucket"
  type        = string
  default     = "s3-file-processor-lambda-bucket"
}

variable "state_bucket_name" {
  description = "name of the s3 bucket that stores terraform state"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "name of the project, used for tagging and state key"
  type        = string
}

variable "metadata_table_name" {
  description = "name of the DynamoDB table that stores S3 object metadata"
  type        = string
  default     = "s3-file-metadata"
}

variable "tags" {
  description = "Tags to add to resources"
  type        = map(string)
}

variable "circleci_project_id" {
  description = "CircleCI project id for the lambda deployment role"
  type        = string
  default     = ""
}
