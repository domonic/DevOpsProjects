.PHONY: help init plan apply destroy test-local test-events lint clean

TERRAFORM_DIR = terraform
ENV ?= dev

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# -----------------------------------------------------------------------------
# Terraform
# -----------------------------------------------------------------------------

init: ## Initialize Terraform
	cd $(TERRAFORM_DIR) && terraform init

plan: ## Plan Terraform changes (ENV=dev|prod)
	cd $(TERRAFORM_DIR) && terraform plan \
		-var-file=environments/$(ENV).tfvars \
		-var="slack_webhook_url=$${SLACK_WEBHOOK_URL}"

apply: ## Apply Terraform changes (ENV=dev|prod)
	cd $(TERRAFORM_DIR) && terraform apply \
		-var-file=environments/$(ENV).tfvars \
		-var="slack_webhook_url=$${SLACK_WEBHOOK_URL}"

destroy: ## Destroy Terraform resources (ENV=dev|prod)
	cd $(TERRAFORM_DIR) && terraform destroy \
		-var-file=environments/$(ENV).tfvars \
		-var="slack_webhook_url=$${SLACK_WEBHOOK_URL}"

# -----------------------------------------------------------------------------
# Testing
# -----------------------------------------------------------------------------

test-local: ## Run local Lambda handler tests (no AWS needed)
	python tests/test_handler_local.py

test-events: ## Send test events to EventBridge (requires AWS credentials)
	aws events put-events --entries file://tests/events/ecs_task_retirement.json
	aws events put-events --entries file://tests/events/ec2_instance_terminated.json
	aws events put-events --entries file://tests/events/eks_fargate_pod_termination.json
	aws events put-events --entries file://tests/events/ec2_scheduled_maintenance.json
	@echo "✅ All test events sent to EventBridge"

# -----------------------------------------------------------------------------
# Kubernetes (Event Exporter)
# -----------------------------------------------------------------------------

deploy-k8s: ## Deploy Kubernetes Event Exporter for Karpenter alerts
	kubectl apply -k kubernetes/event-exporter/

undeploy-k8s: ## Remove Kubernetes Event Exporter
	kubectl delete -k kubernetes/event-exporter/

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------

lint: ## Lint Terraform and Python
	cd $(TERRAFORM_DIR) && terraform fmt -check -recursive
	python -m flake8 $(TERRAFORM_DIR)/lambda/src/ --max-line-length=120

clean: ## Clean build artifacts
	rm -rf $(TERRAFORM_DIR)/lambda/dist/
	rm -rf $(TERRAFORM_DIR)/.terraform/
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
