# gcp-k8s-bare
Terraform project to stand up Kubernetes cluster on Google Cloud Platform

## Introduction
This terraform project makes use of an existing GCP project and provisions all the required resources to have a working Kubernetes cluster.  Additionally, once provisioned a series of services are provisioned on the Kubernetes cluster.

The following GCP entities are created:
* 1 Bastion Server to control ssh access to the cluster
* X Kubernetes Master nodes (variable k8s-master-count)
* Y Kubernetes Worker nodes (variable k8s-worker-count)

The following K8s applications are created:
* N/A

## Required Resources
TBD

## GCP Prerequisites
TBD

## Creating the Environment
Initialize the terraform environment with the `terraform init` command.

Run the command `terraform apply` to bring everything up
## Destroying the Environment
Run the command `terraform destroy` to remove everything.