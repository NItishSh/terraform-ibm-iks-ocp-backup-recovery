variable "ibmcloud_api_key" {
  type        = string
  description = "IBM Cloud API key used to authenticate with the IBM Cloud platform."
  sensitive   = true
}

variable "region" {
  type        = string
  description = "IBM Cloud region where the cluster and BRS instance are located."
  default     = "us-south"
}

variable "prefix" {
  type        = string
  description = "Prefix to prepend to all provisioned resources."
  default     = "brs-vpe"
}

variable "resource_group" {
  type        = string
  description = "Name of an existing resource group to use. If null, a new resource group is created."
  default     = null
}

variable "cluster_id" {
  type        = string
  description = "ID or name of the IKS/ROKS VPC cluster to protect."
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC where the cluster is deployed. Used to look up subnets for the BRS VPE gateway."
}

variable "kube_type" {
  type        = string
  description = "Type of Kubernetes cluster: 'openshift' or 'kubernetes'."
  default     = "kubernetes"
}

variable "existing_brs_instance_crn" {
  type        = string
  description = "CRN of an existing BRS instance. If null, a new BRS instance is created in the cluster's region."
  default     = null
}

variable "brs_source_account_id" {
  type        = string
  description = "Account ID of the IBM Cloud account that owns the cluster VPC. Set this only for cross-account deployments where the BRS instance is in a different account than the cluster. When set, an S2S IAM authorization policy is created. Leave null for same-account deployments."
  default     = null
}

variable "resource_tags" {
  type        = list(string)
  description = "Optional list of user tags to attach to all provisioned resources."
  default     = []
}

variable "access_tags" {
  type        = list(string)
  description = "Optional list of access management tags to attach to all provisioned resources."
  default     = []
}
