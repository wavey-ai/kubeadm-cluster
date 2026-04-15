TF_DIR := terraform

.PHONY: terraform-init terraform-plan terraform-apply terraform-destroy bootstrap validate fmt

terraform-init:
	terraform -chdir=$(TF_DIR) init

terraform-plan:
	terraform -chdir=$(TF_DIR) plan

terraform-apply:
	terraform -chdir=$(TF_DIR) apply

terraform-destroy:
	terraform -chdir=$(TF_DIR) destroy

bootstrap:
	./scripts/bootstrap-cluster.sh

fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive

validate:
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	terraform -chdir=$(TF_DIR) validate
	bash -n scripts/*.sh
