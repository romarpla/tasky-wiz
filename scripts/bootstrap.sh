#!/bin/bash
# One-time setup, run from Cloud Shell or a laptop logged in with `gcloud auth login`.
# Creates the Terraform state bucket and lets GitHub Actions authenticate to GCP
# with Workload Identity Federation (short-lived tokens, no JSON keys in GitHub).
#
# Usage: ./scripts/bootstrap.sh <project-id> <github-owner>/<repo>
set -euo pipefail

PROJECT_ID=$1
GITHUB_REPO=$2
REGION=us-east4
STATE_BUCKET="${PROJECT_ID}-tfstate"
SA_NAME=github-deployer
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud config set project "$PROJECT_ID"
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com storage.googleapis.com serviceusage.googleapis.com

# Terraform remote state, versioned, never public
gcloud storage buckets create "gs://${STATE_BUCKET}" --location="$REGION" \
  --uniform-bucket-level-access --public-access-prevention || true
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning

# Identity used by both pipelines
gcloud iam service-accounts create "$SA_NAME" --display-name="GitHub Actions deployer" || true
for ROLE in roles/editor roles/resourcemanager.projectIamAdmin roles/storage.admin \
            roles/secretmanager.admin roles/container.admin roles/iam.serviceAccountAdmin \
            roles/binaryauthorization.policyEditor; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" --role="$ROLE" --condition=None >/dev/null
done

# Trust GitHub's OIDC tokens, but only from this one repository
gcloud iam workload-identity-pools create github --location=global \
  --display-name="GitHub Actions" || true
gcloud iam workload-identity-pools providers create-oidc github --location=global \
  --workload-identity-pool=github \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='${GITHUB_REPO}'" || true

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
POOL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github"
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/${POOL}/attribute.repository/${GITHUB_REPO}" >/dev/null

echo
echo "Add these as GitHub repository variables (Settings > Secrets and variables > Actions > Variables):"
echo "  GCP_PROJECT_ID     = ${PROJECT_ID}"
echo "  GCP_WIF_PROVIDER   = ${POOL}/providers/github"
echo "  GCP_SA_EMAIL       = ${SA_EMAIL}"
echo "  TF_STATE_BUCKET    = ${STATE_BUCKET}"
echo "  ALERT_EMAIL        = <your email>"
