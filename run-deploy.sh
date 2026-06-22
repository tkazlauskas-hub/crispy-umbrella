#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# One-shot: push to GitHub, bootstrap AWS, deploy staging, test the endpoint.
# Run it from INSIDE the unzipped repo folder (where main.tf and bootstrap/ are).
#
#   chmod +x run-deploy.sh && ./run-deploy.sh
#
# Prerequisites on your machine:
#   - terraform >= 1.9, aws cli, git, curl
#   - aws cli logged in:  aws configure   (region eu-central-1)
#   - a GitHub Personal Access Token (classic, scope "repo") for the push prompt
#
# COST: this creates billable resources (WAF, KMS keys, VPC interface endpoint).
#       A short test costs on the order of ~1 USD. Run ./run-deploy.sh destroy
#       (see bottom) when finished.
# ---------------------------------------------------------------------------
set -euo pipefail

OWNER="tkazlauskas-hub"
REPO="crispy-umbrella"
REGION="eu-central-1"
BUCKET="health-check-tfstate-tk-$(date +%s)"

# ---- destroy mode ---------------------------------------------------------
if [ "${1:-}" = "destroy" ]; then
  echo ">> Destroying staging + bootstrap ..."
  export AWS_REGION="$REGION"
  export TF_STATE_BUCKET="$(cd bootstrap && terraform output -raw state_bucket)"
  export TF_LOCK_TABLE="$(cd bootstrap && terraform output -raw lock_table)"
  export TF_VAR_permissions_boundary_arn="$(cd bootstrap && terraform output -raw permissions_boundary_arn)"
  make destroy ENV=staging || true
  (cd bootstrap && terraform destroy -auto-approve \
      -var="aws_region=$REGION" -var="state_bucket_name=$TF_STATE_BUCKET" \
      -var="github_owner=$OWNER" -var="github_repo=$REPO")
  echo ">> Done."
  exit 0
fi

echo "==> 0/5  Checking prerequisites"
command -v terraform >/dev/null || { echo "ERROR: terraform not installed"; exit 1; }
command -v aws >/dev/null || { echo "ERROR: aws cli not installed"; exit 1; }
aws sts get-caller-identity >/dev/null || { echo "ERROR: aws cli not logged in (run: aws configure)"; exit 1; }
echo "    OK  (account: $(aws sts get-caller-identity --query Account --output text), region: $REGION)"

read -r -p "==> This will PUSH to GitHub and CREATE billable AWS resources. Type 'yes' to continue: " ok
[ "$ok" = "yes" ] || { echo "Aborted."; exit 1; }

echo "==> 1/5  Pushing repo to GitHub (you'll be asked for username + token)"
git remote add origin "https://github.com/${OWNER}/${REPO}.git" 2>/dev/null \
  || git remote set-url origin "https://github.com/${OWNER}/${REPO}.git"
git push -u origin main || git push -u origin main --force
echo "    Pushed to https://github.com/${OWNER}/${REPO}"

echo "==> 2/5  Bootstrap (state backend + OIDC + deploy role + permissions boundary)"
( cd bootstrap
  terraform init -input=false
  terraform apply -auto-approve -input=false \
    -var="aws_region=${REGION}" \
    -var="state_bucket_name=${BUCKET}" \
    -var="github_owner=${OWNER}" \
    -var="github_repo=${REPO}"
)

echo "==> 3/5  Reading bootstrap outputs"
export AWS_REGION="$REGION"
export TF_STATE_BUCKET="$(cd bootstrap && terraform output -raw state_bucket)"
export TF_LOCK_TABLE="$(cd bootstrap && terraform output -raw lock_table)"
export TF_VAR_permissions_boundary_arn="$(cd bootstrap && terraform output -raw permissions_boundary_arn)"
echo "    state_bucket=${TF_STATE_BUCKET}"

echo "==> 4/5  Deploying STAGING (terraform apply)"
make apply ENV=staging
# Commit the provider lock file so versions are pinned (best practice).
if [ -f .terraform.lock.hcl ]; then
  git add .terraform.lock.hcl && git commit -m "chore: pin provider versions (lock file)" && git push || true
fi

echo "==> 5/5  Testing the /health endpoint"
URL="$(terraform output -raw health_endpoint)"
KEY_ID="$(terraform output -raw api_key_id)"
KEY="$(aws apigateway get-api-key --api-key "$KEY_ID" --include-value --query value --output text)"
echo "    Endpoint: $URL"
echo "    --- 200 expected (valid payload):"
curl -s -X POST "$URL" -H "x-api-key: $KEY" -H "Content-Type: application/json" -d '{"payload":{"check":"ok"}}'; echo
echo "    --- 400 expected (missing payload):"
curl -s -X POST "$URL" -H "x-api-key: $KEY" -H "Content-Type: application/json" -d '{"foo":"bar"}'; echo
echo "    --- 403 expected (no API key):"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST "$URL" -H "Content-Type: application/json" -d '{"payload":{}}'

cat <<EOF

==> DONE.
   Repo:     https://github.com/${OWNER}/${REPO}
   Endpoint: ${URL}

   To set up the full GitHub Actions pipeline, add these repo Variables
   (Settings > Secrets and variables > Actions > Variables):
     AWS_DEPLOY_ROLE_ARN      = $(cd bootstrap && terraform output -raw deploy_role_arn)
     AWS_REGION               = ${REGION}
     TF_STATE_BUCKET          = ${TF_STATE_BUCKET}
     TF_LOCK_TABLE            = ${TF_LOCK_TABLE}
     PERMISSIONS_BOUNDARY_ARN = ${TF_VAR_permissions_boundary_arn}
   ...and create Environments 'staging' and 'prod' (prod = Required reviewers).

   TEAR DOWN when finished (to stop charges):   ./run-deploy.sh destroy
EOF
