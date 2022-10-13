# tekton-aws-prerequisites

This repository contains the resources for the demo discussed in the blog [Canary Testing with AWS App Mesh and Tekton
](https://aws.amazon.com/blogs/opensource/canary-testing-with-aws-app-mesh-and-tekton/).

The code provided is for demo purposes only and not ready for production.

## Prerequisites
This demo requires multiple tools to be installed on your machine.

Please make sure that the following tools are installed and ready to use:

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [eksctl](https://eksctl.io/introduction/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [aws-iam-authenticator](https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html)
- [Docker](https://www.docker.com/products/docker-desktop)
- [GitHub CLI](https://github.com/cli/cli#installation)
- [coreutils](https://formulae.brew.sh/formula/coreutils#default)

Further we suggest to use a dedicated AWS Account in order to run this demo.
The install script should be executed with the credentials of an Admin user.

The following articles provide guidance how to setup an AWS Account and configure the required Admin user:

- [Create an AWS Account](https://aws.amazon.com/premiumsupport/knowledge-center/create-and-activate-aws-account/)
- [Create an Admin User](https://docs.aws.amazon.com/IAM/latest/UserGuide/getting-started_create-admin-group.html)
- [Setup your CLI credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html)

The installation took place from a MacOS operating system with bash as the shell environment.

Next a Kubernetes cluster is required in order to deploy Tekton and other related resources. In order to work with the demo script please use the official eksctl command line tool to create the cluster.
Please find below a command which creates a simple two node cluster:

```console
$ eksctl create cluster canary-testing-demo
```

Please wait until the cluster has been provisioned successfully and you obtained the kubeconfig file.
You can test the successfull installation by running:

```console
$ eksctl get clusters
$ kubectl get nodes
```

If both of the above commands complete successfully please continue with the installation steps.

## Install demo environment

Clone the repository and switch into the directory

```console
$ git clone TO BE UPDATED
$ cd tekton-aws-prerequisites
```

Open the file called install.sh with your favorite text editor and set the following environment variables

```console
# Your AWS Account ID
export AWS_ACCOUNT_ID=""

# Your AWS region (e.g. eu-central-1)
export AWS_REGION=""

# Name of your EKS Cluster
export EKS_CLUSTER_NAME=""

# Name of your Github organization (for personal Github accounts it is your username)
export GITHUB_ORG_NAME=""

# Name of the forked app repo
export GITHUB_APP_REPO_NAME=""

# Name of the forked deploy repo
export GITHUB_DEPLOYMENT_REPO_NAME=

```

After updating these environment variables, save the file and install the script with the following commands

```console
$ chmod u+x install.sh
$ ./install.sh
```

The script installs the environment and takes approximately 5 minutes to complete (depends on your internet connectivity). Please keep your Terminal open until everyhting is installed and the output section is displayed.

## Uninstall

To uninstall all resources, please switch back into the root folder:

```console
$ cd tekton-aws-prerequisites
```

Open the file called uninstall.sh with your favorite text editor and set the following environment variables

```console
#Your AWS Account ID
export AWS_ACCOUNT_ID=""

#Your AWS region (e.g. eu-central-1)
export AWS_REGION=""

#Name of your EKS Cluster
export EKS_CLUSTER_NAME=""
```

After updating the uninstall.sh script, please execute the file with the following commands:

```console
$ chmod u+x uninstall.sh
$ ./uninstall.sh
```

Wait until all resources have been removed. We suggest to double check your AWS account for not cleaned up resources which needs to be removed manually.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
