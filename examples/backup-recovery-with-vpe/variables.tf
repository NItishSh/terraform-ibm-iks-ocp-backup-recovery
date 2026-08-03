variable "ibmcloud_api_key" {
  type        = string
  description = "The IBM Cloud API Key."
  sensitive   = true
}

variable "region" {
  type        = string
  description = "Region where resources are created."
  default     = "us-east"
}

variable "prefix" {
  type        = string
  description = "Prefix for name of all resources created by this example."
  validation {
    error_message = "Prefix must begin and end with a letter and contain only letters, numbers, and - characters."
    condition     = can(regex("^([A-z]|[a-z][-a-z0-9]*[a-z0-9])$", var.prefix))
  }
}

variable "resource_group" {
  type        = string
  description = "An existing resource group name to use for this example. If null, a new resource group is created."
  default     = null
}

variable "cluster_name_id" {
  type        = string
  description = <<EOT
Name or ID of an existing IKS VPC cluster to protect.
If null (default), this example creates a new VPC and IKS cluster automatically.
If provided, the example uses that existing cluster and no new VPC or cluster resources are created.
EOT
  default     = null
}

variable "existing_brs_instance_crn" {
  type        = string
  description = "CRN of an existing BRS instance to use. If null, a new BRS instance is created in the cluster's region."
  default     = null
}

variable "brs_source_account_id" {
  type        = string
  description = "IBM Cloud account ID of the account that owns the cluster VPC. Set this only for cross-account deployments where the BRS instance lives in a different IBM Cloud account than the cluster. When set, an S2S IAM authorization policy is created (apply from the BRS/target account). Leave null for same-account deployments."
  default     = null
}

variable "cluster_config_endpoint_type" {
  type        = string
  description = "The type of endpoint to use for cluster config access: 'default', 'private', 'vpe', or 'link'."
  default     = "default"

  validation {
    condition     = contains(["default", "private", "vpe", "link"], var.cluster_config_endpoint_type)
    error_message = "`cluster_config_endpoint_type` must be 'default', 'private', 'vpe', or 'link'."
  }
}

variable "resource_tags" {
  type        = list(string)
  description = "Optional list of tags to attach to all provisioned resources."
  default     = []
}

variable "access_tags" {
  type        = list(string)
  description = "A list of access management tags to apply to all provisioned resources."
  default     = []
}
