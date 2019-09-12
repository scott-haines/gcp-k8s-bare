variable "project-name" {}
variable "k8s-bastion-fqdn" {}
variable "k8s-api-fqdn" {}
variable "k8s-traefik-fqdn" {}
variable "dns-k8s-bastion-username" {}
variable "dns-k8s-bastion-password" {}
variable "dns-k8s-api-username" {}
variable "dns-k8s-api-password" {}
variable "ssh-username" {}
variable "ssh-private-key" {}

variable "k8s-master-count" {}
variable "k8s-worker-count" {}
variable "k8s-service-cluster-ip-cidr" {}
variable "k8s-pod-network-cidr" {}
