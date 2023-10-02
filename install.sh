#!/bin/bash

set -e

env_vars=("AWS_ACCOUNT_ID" "AWS_REGION" "EKS_CLUSTER_NAME" "GITHUB_ORG_NAME" "GITHUB_APP_REPO_NAME" "GITHUB_DEPLOYMENT_REPO_NAME")

export AWS_ACCOUNT_ID=""
export AWS_REGION=""
export EKS_CLUSTER_NAME=""
export GITHUB_ORG_NAME=""
export GITHUB_APP_REPO_NAME="aws-tekton-canary-testing-app"
export GITHUB_DEPLOYMENT_REPO_NAME="aws-tekton-canary-testing-deploy"

# Check for prerequisites
for tool in aws kubectl eksctl aws-iam-authenticator kubectl helm sed gh docker sha256sum
do
    if ! [ -x "$(command -v $tool)" ]; then
        echo "[ERROR] $(date +"%T") $tool is not installed. Please install $tool before running the script again" >&2
        exit 1
    fi
done

# Check for environment variables
for each in "${env_vars[@]}"; do
    if [ -z "${!each}" ]; then
        echo "$each is not defined"
        exit 1
    fi
done

echo "generate webhook secret"
export WEBHOOK_SECRET=$(date +%s | sha256sum | base64 | head -c 16 ; echo) > /dev/null 

echo "create ecr repository for frontend app"
aws ecr create-repository \
    --repository-name catalog-frontend \
    --image-scanning-configuration scanOnPush=true > /dev/null

echo "create ecr repository for backend app"
aws ecr create-repository \
    --repository-name catalog-backend \
    --image-scanning-configuration scanOnPush=true > /dev/null

echo "login to ecr"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo "build frontend app"
docker buildx build --platform=linux/amd64 -t catalog-frontend apps/demo-app-frontend/.

echo "upload frontend app to ecr"
docker tag catalog-frontend:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/catalog-frontend:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/catalog-frontend:latest

echo "build backend app"
docker buildx build --platform=linux/amd64 -t catalog-backend:v1.0.0 apps/demo-app-backend/.

echo "upload backend app to ecr"
docker tag catalog-backend:v1.0.0 ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/catalog-backend:v1.0.0
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/catalog-backend:v1.0.0

echo "enable oidc provider on eks cluster for irsa"
eksctl utils associate-iam-oidc-provider --cluster=${EKS_CLUSTER_NAME} --approve

echo "add helm chart for app mesh controller"
helm repo add eks https://aws.github.io/eks-charts

echo "install app mesh crds"
kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"

echo "create namespaces and tag them"
kubectl create ns appmesh-system
kubectl create ns apps
kubectl label ns apps mesh=tekton-canary-mesh
kubectl label ns apps appmesh.k8s.aws/sidecarInjectorWebhook=enabled
kubectl label ns apps gateway=ingress-gw

echo "create service account for app mesh controller"
eksctl create iamserviceaccount \
    --cluster $EKS_CLUSTER_NAME \
    --namespace appmesh-system \
    --name appmesh-controller \
    --attach-policy-arn  arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
    --override-existing-serviceaccounts \
    --approve > /dev/null

echo "deploy app mesh controller"
helm upgrade -i appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system \
    --set region=$AWS_REGION \
    --set serviceAccount.create=false \
    --set serviceAccount.name=appmesh-controller > /dev/null

echo "bootstrap iam policies for app mesh services"
sed -i'' -e "s/AWS_REGION/${AWS_REGION}/g" policies/frontend-service-proxy-auth.json
sed -i'' -e "s/AWS_ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" policies/frontend-service-proxy-auth.json

sed -i'' -e "s/AWS_REGION/${AWS_REGION}/g" policies/backend-service-proxy-auth.json
sed -i'' -e "s/AWS_ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" policies/backend-service-proxy-auth.json

sed -i'' -e "s/AWS_REGION/${AWS_REGION}/g" policies/ingress-gw-proxy-auth.json
sed -i'' -e "s/AWS_ACCOUNT_ID/${AWS_ACCOUNT_ID}/g" policies/ingress-gw-proxy-auth.json

echo "create iam policies for app mesh services"
aws iam create-policy --policy-name frontend-svc-proxy-auth --policy-document file://policies/frontend-service-proxy-auth.json > /dev/null
aws iam create-policy --policy-name backend-svc-proxy-auth --policy-document file://policies/backend-service-proxy-auth.json > /dev/null
aws iam create-policy --policy-name ingress-gw-proxy-auth --policy-document file://policies/ingress-gw-proxy-auth.json > /dev/null

echo "create k8s service account for frontend proxy"
eksctl create iamserviceaccount \
    --cluster $EKS_CLUSTER_NAME \
    --namespace apps \
    --name frontend-service \
    --attach-policy-arn  arn:aws:iam::${AWS_ACCOUNT_ID}:policy/frontend-svc-proxy-auth \
    --override-existing-serviceaccounts \
    --approve > /dev/null

echo "create k8s service account for backend proxy"
eksctl create iamserviceaccount \
    --cluster $EKS_CLUSTER_NAME \
    --namespace apps \
    --name backend-service \
    --attach-policy-arn  arn:aws:iam::${AWS_ACCOUNT_ID}:policy/backend-svc-proxy-auth \
    --override-existing-serviceaccounts \
    --approve > /dev/null

echo "create k8s service account for ingress proxy"
eksctl create iamserviceaccount \
    --cluster $EKS_CLUSTER_NAME \
    --namespace apps \
    --name proddetail-envoy-proxies \
    --attach-policy-arn  arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ingress-gw-proxy-auth \
    --override-existing-serviceaccounts \
    --approve > /dev/null

echo "install mesh crd"
kubectl create -f mesh.yaml

echo "deploy frontend service"
helm install -n apps -f app-mesh-frontend-resources/values.yaml frontend-deployment ./app-mesh-frontend-resources \
    --set frontend.image.repository=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/catalog-frontend

echo "deploy backend service"
helm install -n apps -f app-mesh-backend-resources/values.yaml backend-deployment ./app-mesh-backend-resources \
    --set detail.image.repository=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/catalog-backend

# Install Tekton Resources
echo "deploy Tekton Operator"
kubectl apply -f https://storage.googleapis.com/tekton-releases/operator/latest/release.yaml

echo "install Tekton Operator config"
kubectl apply -f tekton-resources/operator-config.yaml

echo "install AWS EBS CSI driver"
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa \
  --namespace kube-system \
  --cluster $EKS_CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --role-only \
  --role-name AmazonEKS_EBS_CSI_DriverRole > /dev/null

echo "create k8s service account for ebs csi driver"
eksctl create addon --name aws-ebs-csi-driver --cluster $EKS_CLUSTER_NAME \
    --service-account-role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole \
    --force > /dev/null

echo "install Tekton resources for app build pipeline"
helm install -f tekton-resources/tekton-catalog-backend-app-pipeline/values.yaml tekton-catalog-backend-app-pipeline \
    ./tekton-resources/tekton-catalog-backend-app-pipeline \
    --namespace apps-build \
    --create-namespace \
    --set aws.accountID=${AWS_ACCOUNT_ID} \
    --set aws.region=${AWS_REGION} \
    --set github.secretToken=${WEBHOOK_SECRET}

echo "install Tekton resources for app deploy pipeline"
helm install -f tekton-resources/tekton-catalog-backend-deploy-pipeline/values.yaml tekton-catalog-backend-deploy-pipeline \
    ./tekton-resources/tekton-catalog-backend-deploy-pipeline \
    --namespace apps-build \
    --set aws.accountId=${AWS_ACCOUNT_ID} \
    --set aws.region=${AWS_REGION} \
    --set github.secretToken=${WEBHOOK_SECRET}

echo "create sa for tekton pipeline"
eksctl create iamserviceaccount \
    --cluster=${EKS_CLUSTER_NAME} \
    --name=pipeline-sa \
    --namespace=apps-build \
    --attach-policy-arn="arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser" \
    --override-existing-serviceaccounts \
    --approve > /dev/null

echo "extract load balancer urls"
export FRONTEND_ALB_ENDPOINT=$(kubectl -n apps get svc ingress-gw -o jsonpath="{.status.loadBalancer.ingress[].hostname}")
export TEKTON_APP_PIPELINE_ENDPOINT=$(kubectl -n apps-build get svc el-gitcommit-listener-interceptor -o jsonpath="{.status.loadBalancer.ingress[].hostname}")
export TEKTON_DEPLOY_PIPELINE_ENDPOINT=$(kubectl -n apps-build get svc el-app-deploy-eventlistener -o jsonpath="{.status.loadBalancer.ingress[].hostname}")

echo "create webhook configs"
sed -i'' -e "s/ENDPOINT/${TEKTON_APP_PIPELINE_ENDPOINT}/g" webhooks/aws-tekton-canary-testing-app.json
sed -i'' -e "s/SECRET/${WEBHOOK_SECRET}/g" webhooks/aws-tekton-canary-testing-app.json

sed -i'' -e "s/ENDPOINT/${TEKTON_DEPLOY_PIPELINE_ENDPOINT}/g" webhooks/aws-tekton-canary-testing-deploy.json
sed -i'' -e "s/SECRET/${WEBHOOK_SECRET}/g" webhooks/aws-tekton-canary-testing-deploy.json

echo "update webhook configs"
gh api /repos/${GITHUB_ORG_NAME}/${GITHUB_APP_REPO_NAME}/hooks --input webhooks/aws-tekton-canary-testing-app.json > /dev/null
gh api /repos/${GITHUB_ORG_NAME}/${GITHUB_DEPLOYMENT_REPO_NAME}/hooks --input webhooks/aws-tekton-canary-testing-deploy.json > /dev/null

echo "#########################################################################################################################"
echo "TEKTON_APP_PIPELINE_ENDPOINT => http://${TEKTON_APP_PIPELINE_ENDPOINT}:8080"
echo "FRONTEND_ALB_ENDPOINT => http://${FRONTEND_ALB_ENDPOINT}"
echo "TEKTON_DEPLOY_PIPELINE_ENDPOINT => http://${TEKTON_DEPLOY_PIPELINE_ENDPOINT}:8080"
echo "#########################################################################################################################"

echo "resources deployed successfully"
