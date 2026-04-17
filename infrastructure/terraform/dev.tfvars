## Terrastate
region                = var.region
account_id            = var.account_id
state_backend         = "s3"
state_bucket          = var.state_bucket_name
state_dynamodb_table  = "terraform-state-lock"
state_key             = "${var.project_name}/{{ current.dir }}/terraform.tfstate"
state_auto_remove_old = true
circleci_project_id   = var.circleci_project_id

## Global
stage = "dev"

tags = {
  terraform    = "true"
  project      = var.project-name
  stage        = "dev"
}