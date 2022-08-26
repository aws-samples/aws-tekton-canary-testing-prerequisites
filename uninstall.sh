#!/bin/bash

export AWS_ACCOUNT_ID=""
export AWS_REGION=""
export EKS_CLUSTER_NAME=""
export GITHUB_ORG_NAME=""
export GITHUB_APP_REPO_NAME="aws-tekton-canary-testing-app"
export GITHUB_DEPLOYMENT_REPO_NAME="aws-tekton-canary-testing-deploy"

echo "remove ecr repository for frontend app"
aws ecr delete-repository \
    --repository-name=catalog-frontend \
    --force

echo "remove ecr repository for backend app"
aws ecr delete-repository \
    --repository-name=catalog-backend \
    --force

echo "delete webhooks on github"
HOOK_ID_APP=$(gh api /repos/${GITHUB_ORG_NAME}/${GITHUB_APP_REPO_NAME}/hooks | jq .[0].id)
gh api --method DELETE /repos/${GITHUB_ORG_NAME}/${GITHUB_APP_REPO_NAME}/hooks/${HOOK_ID_APP}

HOOK_ID_DEPLOY=$(gh api /repos/${GITHUB_ORG_NAME}/${GITHUB_DEPLOYMENT_REPO_NAME}/hooks | jq .[0].id)
gh api --method DELETE /repos/${GITHUB_ORG_NAME}/${GITHUB_DEPLOYMENT_REPO_NAME}/hooks/${HOOK_ID_DEPLOY}

echo "delete EKS cluster"
eksctl delete cluster $EKS_CLUSTER_NAME

echo "remove iam policies"
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/backend-svc-proxy-auth
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/frontend-svc-proxy-auth
aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ingress-gw-proxy-auth