.PHONY: help tf tf-init tf-apply tf-plan tf-role tf-delete build-lambda clean lint format validate

SHELL := /bin/bash
STAGE ?= dev
AWS_REGION ?= eu-central-1

LAMBDA_BUILD_DIR := infrastructure/terraform/lambda
LAMBDA_ZIP := $(LAMBDA_BUILD_DIR)/s3-file-processor-lambda.zip

# Color output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

tf: tf-init tf-plan tf-apply
tf-role: tf-init-role tf-apply-role

help:
	@echo "$(GREEN)s3-metadata-processor - Makefile targets$(NC)"
	@echo "Usage: make [target] STAGE=dev|test|prod"
	@echo ""
	@echo "Infrastructure targets:"
	@echo "  $(YELLOW)tf-init$(NC)        Initialize Terraform for current stage"
	@echo "  $(YELLOW)tf-plan$(NC)        Plan Terraform changes"
	@echo "  $(YELLOW)tf-apply$(NC)       Apply Terraform changes"
	@echo "  $(YELLOW)tf-delete$(NC)      Destroy all Terraform resources (DESTRUCTIVE)"
	@echo ""
	@echo "Build targets:"
	@echo "  $(YELLOW)build-lambda$(NC)   Build and zip Lambda function"
	@echo "  $(YELLOW)clean$(NC)          Clean build artifacts"
	@echo ""
	@echo "Code quality targets:"
	@echo "  $(YELLOW)lint$(NC)           Run ESLint on source code"
	@echo "  $(YELLOW)format$(NC)         Format code with Prettier"
	@echo "  $(YELLOW)validate$(NC)       Validate infrastructure files"

# Build targets
build-lambda: | $(LAMBDA_BUILD_DIR)
	@echo "$(GREEN)Building Lambda package...$(NC)"
	@cp src/lambda.cjs $(LAMBDA_BUILD_DIR)/index.js
	@cd $(LAMBDA_BUILD_DIR) && zip -q -r s3-file-processor-lambda.zip index.js && cd ../../..
	@echo "$(GREEN)✓ Built $(LAMBDA_ZIP)$(NC)"

$(LAMBDA_BUILD_DIR):
	@mkdir -p $(LAMBDA_BUILD_DIR)

clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(LAMBDA_BUILD_DIR)
	@find . -name "*.tfstate*" -type f -delete
	@echo "$(GREEN)✓ Cleaned build artifacts$(NC)"

# Code quality targets
lint:
	@command -v eslint >/dev/null 2>&1 || { echo "$(RED)ESLint not installed. Run: npm install$(NC)"; exit 1; }
	@echo "$(YELLOW)Running ESLint...$(NC)"
	@npx eslint src/ --format=stylish
	@echo "$(GREEN)✓ Linting complete$(NC)"

format:
	@command -v prettier >/dev/null 2>&1 || { echo "$(RED)Prettier not installed. Run: npm install$(NC)"; exit 1; }
	@echo "$(YELLOW)Formatting code...$(NC)"
	@npx prettier --write "src/**/*.js"
	@echo "$(GREEN)✓ Formatting complete$(NC)"

format-check:
	@command -v prettier >/dev/null 2>&1 || { echo "$(RED)Prettier not installed. Run: npm install$(NC)"; exit 1; }
	@echo "$(YELLOW)Checking code format...$(NC)"
	@npx prettier --check "src/**/*.js"
	@echo "$(GREEN)✓ Format check complete$(NC)"

validate: validate-terraform

validate-terraform:
	@echo "$(YELLOW)Validating Terraform files...$(NC)"
	@cd infrastructure/terraform && terraform fmt -check -recursive . || true
	@cd infrastructure/terraform && terraform validate || { echo "$(RED)Terraform validation failed$(NC)"; exit 1; }
	@cd ../.. && echo "$(GREEN)✓ Terraform validation complete$(NC)"

# Terraform targets
tf-init:
	@echo "$(YELLOW)Initializing Terraform for $(STAGE)...$(NC)"
	@cd infrastructure/terraform && \
		aws-sso-util login --all && \
		source awsume "ts-playground-$(STAGE).AdministratorAccess" && \
		terrastate --var-file="$(STAGE).tfvars" && \
		terraform init -upgrade && \
		echo "$(GREEN)✓ Terraform initialized$(NC)" || \
		{ echo "$(RED)Terraform init failed$(NC)"; exit 1; }

tf-apply: build-lambda validate-terraform
	@echo "$(YELLOW)Applying Terraform changes for $(STAGE)...$(NC)"
	@cd infrastructure/terraform && \
		source awsume "ts-playground-$(STAGE).AdministratorAccess" && \
		terraform plan -var-file="$(STAGE).tfvars" && \
		terraform apply -var-file="$(STAGE).tfvars" && \
		echo "$(GREEN)✓ Terraform apply complete$(NC)" || \
		{ echo "$(RED)Terraform apply failed$(NC)"; exit 1; }

tf-init-role: validate-terraform
	@echo "$(YELLOW)Initializing Terraform for $(STAGE)...$(NC)"
	@cd infrastructure/iam-roles && \
		aws-sso-util login --all && \
		source awsume "ts-playground-$(STAGE).AdministratorAccess" && \
		terrastate --var-file="../terraform/$(STAGE).tfvars" && \
		terraform init -upgrade && \
		echo "$(GREEN)✓ Terraform initialized$(NC)" || \
		{ echo "$(RED)Terraform init failed$(NC)"; exit 1; }

tf-apply-role: validate-terraform
	@echo "$(YELLOW)Applying Terraform changes for $(STAGE)...$(NC)"
	@cd infrastructure/iam-roles && \
		source awsume "ts-playground-$(STAGE).AdministratorAccess" && \
		terraform plan -var-file="../terraform/$(STAGE).tfvars" && \
		terraform apply -var-file="../terraform/$(STAGE).tfvars" && \
		echo "$(GREEN)✓ Terraform apply complete$(NC)" || \
		{ echo "$(RED)Terraform apply failed$(NC)"; exit 1; }

tf-delete:
	@echo "$(RED)WARNING: This will destroy all infrastructure for $(STAGE)!$(NC)"
	@read -p "Type 'yes' to continue: " confirm && \
	[ "$$confirm" = "yes" ] || { echo "Aborted."; exit 1; }
	@echo "$(YELLOW)Destroying infrastructure...$(NC)"
	@cd infrastructure/terraform && \
		terraform destroy -var-file="$(STAGE).tfvars" -auto-approve && \
		echo "$(GREEN)✓ Infrastructure destroyed$(NC)" || \
		{ echo "$(RED)Terraform destroy failed$(NC)"; exit 1; }

# Development helpers
logs-lambda:
	@echo "$(YELLOW)Tailing Lambda logs for $(STAGE)...$(NC)"
	@aws logs tail /aws/lambda/s3-file-processor-lambda-$(STAGE) --follow --region $(AWS_REGION) || \
		{ echo "$(RED)Failed to fetch logs$(NC)"; exit 1; }

logs-errors:
	@echo "$(YELLOW)Showing Lambda errors for $(STAGE)...$(NC)"
	@aws logs filter-log-events \
		--log-group-name /aws/lambda/s3-file-processor-lambda-$(STAGE) \
		--filter-pattern "[ERROR]" \
		--region $(AWS_REGION) || \
		{ echo "$(RED)Failed to fetch error logs$(NC)"; exit 1; }
