# Convenience wrapper around Terraform. Works for any environment (cqa, prd, ...).
# Usage: make plan ENV=staging   |   make apply ENV=prod
#
# Backend values come from the environment (the same variables CI uses):
#   TF_STATE_BUCKET, TF_LOCK_TABLE, AWS_REGION
#
# Using a custom recipe prefix (>) so the file does not depend on literal tabs.
.RECIPEPREFIX = >
.PHONY: help init fmt validate plan apply destroy test

ENV ?= staging
AWS_REGION ?= eu-central-1

help:
> @echo "Targets: init | fmt | validate | plan | apply | destroy | test"
> @echo "Set ENV=staging|prod (default: staging)."

init:
> terraform init \
>   -backend-config="bucket=$(TF_STATE_BUCKET)" \
>   -backend-config="dynamodb_table=$(TF_LOCK_TABLE)" \
>   -backend-config="region=$(AWS_REGION)"
> terraform workspace select $(ENV) || terraform workspace new $(ENV)

fmt:
> terraform fmt -recursive

validate:
> terraform validate

plan: init
> terraform plan -var-file="$(ENV).tfvars"

apply: init
> terraform apply -var-file="$(ENV).tfvars" -auto-approve

destroy: init
> terraform destroy -var-file="$(ENV).tfvars"

test:
> pip install -r tests/requirements.txt
> pytest -q
