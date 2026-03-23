########################################################################################################################
# Input variables
########################################################################################################################
variable "ibmcloud_api_key" {
  type        = string
  description = "The IBM Cloud API Key."
  sensitive   = true
}

variable "resource_group" {
  type        = string
  description = "An existing resource group name to use for this example, if unset a new resource group will be created"
  default     = null
}

variable "prefix" {
  type        = string
  description = "Prefix for name of all resource created by this example"
  validation {
    error_message = "Prefix must begin and end with a letter and contain only letters, numbers, and - characters."
    condition     = can(regex("^([A-z]|[a-z][-a-z0-9]*[a-z0-9])$", var.prefix))
  }
}

variable "resource_tags" {
  type        = list(string)
  description = "Optional list of tags to be added to created resources"
  default     = []
}

variable "access_tags" {
  type        = list(string)
  description = "A list of access tags to apply to the resources created by the module."
  default     = []
}

variable "region" {
  type        = string
  description = "Region where resources are created."
  default     = "us-east"
}

variable "cluster_name_id" {
  type        = string
  description = <<EOT
Name or ID of the existing Kubernetes cluster to protect.
If left empty (null, which is the default), this example will automatically create a new VPC
and provision a Kubernetes cluster for you.
If you provide a value, the module will use that existing cluster instead of creating a new one.
EOT
  default     = null
}

variable "dsc_storage_class" {
  type        = string
  description = "Storage class to use for the Data Source Connector persistent volume. By default, it uses 'ibmc-vpc-block-metro-5iops-tier' for VPC clusters and 'ibmc-block-silver' for Classic clusters."
  default     = null
}

variable "existing_brs_instance_crn" {
  type        = string
  description = "CRN of an existing BRS instance to use. If not provided, a new instance will be created."
  default     = null
}

variable "classic_cluster" {
  type        = bool
  description = "Set to true to provision a Classic cluster, false to provision a VPC cluster."
  default     = false
}

variable "datacenter" {
  type        = string
  description = "The classic infrastructure datacenter where the cluster is created. Only used if classic_cluster is true."
  default     = "dal10"
}

variable "recovery_mode" {
  type        = string
  description = "One-place recovery mode: disabled, selective, full, or cross. Cross restores to a different registered cluster."
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "selective", "full", "cross"], var.recovery_mode)
    error_message = "recovery_mode must be one of: disabled, selective, full, cross."
  }
}

variable "recovery_name" {
  type        = string
  description = "Optional recovery task name. If null, the example generates one from prefix and mode."
  default     = null
}

variable "recovery_action" {
  type        = string
  description = "Kubernetes recovery action. Use RecoverNamespaces, RecoverPVs, or RecoverApps."
  default     = "RecoverNamespaces"
}

variable "recovery_snapshot_id" {
  type        = string
  description = "Snapshot ID for selective or cross recovery mode."
  default     = null

  validation {
    condition = (
      !contains(["selective", "cross"], var.recovery_mode) ||
      try(trimspace(var.recovery_snapshot_id), "") != ""
    )
    error_message = "recovery_snapshot_id is required when recovery_mode is selective or cross."
  }
}

variable "recovery_snapshot_ids" {
  type        = list(string)
  description = "Snapshot IDs for full recovery mode."
  default     = []

  validation {
    condition     = var.recovery_mode != "full" || length(var.recovery_snapshot_ids) > 0
    error_message = "recovery_snapshot_ids must contain at least one snapshot ID when recovery_mode is full."
  }
}

variable "recovery_protection_group_id" {
  type        = string
  description = "Optional protection group ID filter passed to recovery objects."
  default     = null
}

variable "recovery_target_source_registration_id" {
  type        = string
  description = "Target source registration ID for cross recovery mode (format tenant::id or tenant/::id)."
  default     = null

  validation {
    condition = (
      var.recovery_mode != "cross" ||
      try(trimspace(var.recovery_target_source_registration_id), "") != ""
    )
    error_message = "recovery_target_source_registration_id is required when recovery_mode is cross."
  }
}

variable "enable_auto_recovery" {
  type        = bool
  description = "Set to true to automatically run namespace recovery from this same example once a snapshot is available."
  default     = false
}

variable "auto_recovery_name" {
  type        = string
  description = "Recovery task name for automatic recovery mode."
  default     = "kubernetes-example-auto-recovery"
}

variable "auto_recovery_snapshot_id" {
  type        = string
  description = "Snapshot ID used by automatic recovery mode. Required when enable_auto_recovery is true and recoveries is empty."
  default     = null
}

variable "auto_recovery_protection_group_id" {
  type        = string
  description = "Optional protection group ID filter for automatic recovery snapshot selection. If null, first created protection group is used."
  default     = null
}

variable "recoveries" {
  type        = any
  description = "Optional advanced recoveries list passed directly to module input recoveries. If set, this takes precedence over built-in recovery variables."
  default     = []
}
