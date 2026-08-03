##############################################################################
# Authentication
##############################################################################

variable "ibmcloud_api_key" {
  type        = string
  description = "IBM Cloud API key for the TARGET account — the account that owns the BRS instance. The S2S IAM authorization policy is also created in this account."
  sensitive   = true
}

variable "source_ibmcloud_api_key" {
  type        = string
  description = "IBM Cloud API key for the SOURCE account — the account that owns the IKS cluster and its VPC. The VPEG is created in this account."
  sensitive   = true
}

variable "source_account_id" {
  type        = string
  description = "IBM Cloud account ID of the SOURCE account (cluster/VPC account). Used to scope the S2S IAM authorization policy so that the VPC endpoint-gateway service in the source account is authorized to target the BRS instance in the target account."
}

##############################################################################
# Regions
##############################################################################

variable "region" {
  type        = string
  description = "IBM Cloud region for the source-account cluster and VPC. The VPEG is created in this region."
  default     = "us-south"
}

variable "brs_region" {
  type        = string
  description = "IBM Cloud region for the target-account BRS instance. Defaults to var.region (same region as the cluster)."
  default     = null
}

##############################################################################
# Naming / grouping
##############################################################################

variable "prefix" {
  type        = string
  description = "Prefix applied to all resource names created by this example."
  validation {
    condition     = can(regex("^([A-Za-z]|[A-Za-z][-a-z0-9]*[a-z0-9])$", var.prefix))
    error_message = "Prefix must begin and end with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "source_resource_group" {
  type        = string
  description = "Existing resource group name in the SOURCE account for the cluster and VPC. If null a new resource group is created."
  default     = null
}

variable "target_resource_group" {
  type        = string
  description = "Existing resource group name in the TARGET account for the BRS instance. If null a new resource group is created."
  default     = null
}

##############################################################################
# Cluster (source account)
##############################################################################

variable "cluster_name_id" {
  type        = string
  description = "Name or ID of an existing IKS VPC cluster in the source account. Leave null (default) to create a new VPC and cluster."
  default     = null
}

variable "cluster_config_endpoint_type" {
  type        = string
  description = "Cluster config endpoint type: 'default', 'private', 'vpe', or 'link'."
  default     = "default"

  validation {
    condition     = contains(["default", "private", "vpe", "link"], var.cluster_config_endpoint_type)
    error_message = "Must be 'default', 'private', 'vpe', or 'link'."
  }
}

##############################################################################
# BRS instance (target account)
##############################################################################

variable "existing_brs_instance_crn" {
  type        = string
  description = "CRN of an existing BRS instance in the TARGET account. If null a new BRS instance is created."
  default     = null
}

##############################################################################
# Tags
##############################################################################

variable "resource_tags" {
  type        = list(string)
  description = "Optional list of user tags to attach to all provisioned resources."
  default     = []
}

variable "access_tags" {
  type        = list(string)
  description = "Optional list of access management tags to apply to all provisioned resources."
  default     = []
}
