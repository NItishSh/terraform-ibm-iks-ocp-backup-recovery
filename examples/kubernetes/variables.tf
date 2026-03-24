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
  description = "One-place recovery mode: disabled, selective, full, cross, or auto. Auto triggers a run, discovers latest namespace snapshot, and restores in the same apply."
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "selective", "full", "cross", "auto"], var.recovery_mode)
    error_message = "recovery_mode must be one of: disabled, selective, full, cross, auto."
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
  description = "Optional legacy/manual snapshot ID override. Built-in selective, full, cross, and auto modes now discover snapshots automatically."
  default     = null
}

variable "recovery_snapshot_ids" {
  type        = list(string)
  description = "Optional legacy/manual snapshot ID list override. Built-in full mode now discovers the latest compatible snapshot set automatically."
  default     = []
}

variable "recovery_protection_group_id" {
  type        = string
  description = "Optional protection group ID filter used during snapshot discovery and passed to recovery objects. If null, the first protection group created by this example is used."
  default     = null
}

variable "recovery_target_source_registration_id" {
  type        = string
  description = "Target source registration ID for cross recovery mode (format tenant::id or tenant/::id). This remains required because the destination cluster cannot be inferred safely."
  default     = null

  validation {
    condition = (
      var.recovery_mode != "cross" ||
      try(trimspace(var.recovery_target_source_registration_id), "") != ""
    )
    error_message = "recovery_target_source_registration_id is required when recovery_mode is cross."
  }
}

variable "auto_run_backup_before_recovery" {
  type        = bool
  description = "When recovery_mode is auto, trigger an on-demand backup run before discovering snapshot IDs for recovery."
  default     = true
}

variable "auto_recovery_run_type" {
  type        = string
  description = "Backup run type used by auto mode when auto_run_backup_before_recovery is true."
  default     = "kRegular"

  validation {
    condition     = contains(["kRegular", "kFull", "kLog", "kSystem", "kHydrateCDP", "kStorageArraySnapshot"], var.auto_recovery_run_type)
    error_message = "auto_recovery_run_type must be one of: kRegular, kFull, kLog, kSystem, kHydrateCDP, kStorageArraySnapshot."
  }
}

variable "auto_recovery_wait_seconds" {
  type        = number
  description = "Wait duration in seconds after on-demand backup trigger before snapshot discovery in auto mode."
  default     = 300

  validation {
    condition     = var.auto_recovery_wait_seconds >= 30
    error_message = "auto_recovery_wait_seconds must be at least 30 seconds."
  }
}

variable "recoveries" {
  type        = any
  description = "Optional advanced recoveries list passed directly to module input recoveries. If set, this takes precedence over built-in recovery variables."
  default     = []
}
