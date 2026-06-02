##############################################################################
# Input Variables
##############################################################################

variable "ibmcloud_api_key" {
  description = "The IBM Cloud API key"
  type        = string
  sensitive   = true
}

variable "prefix" {
  description = "Prefix for naming resources"
  type        = string
  default     = "bkp-rcv"
}

variable "region" {
  description = "IBM Cloud region where resources will be created"
  type        = string
  default     = "us-south"
}

variable "resource_group" {
  description = "Name of existing resource group to use. If null, a new resource group will be created."
  type        = string
  default     = null
}

variable "resource_tags" {
  description = "List of tags to apply to resources"
  type        = list(string)
  default     = ["terraform", "backup-recovery-example"]
}

variable "access_tags" {
  description = "List of access tags to apply to resources"
  type        = list(string)
  default     = []
}

##############################################################################
# Cluster Configuration
##############################################################################

variable "source_cluster_name_id" {
  description = "Name or ID of existing source cluster. If null, a new cluster will be created."
  type        = string
  default     = null
}

variable "target_cluster_name_id" {
  description = "Name or ID of existing target cluster. If null, a new cluster will be created."
  type        = string
  default     = null
}

##############################################################################
# BRS Instance Configuration
##############################################################################

variable "existing_brs_instance_crn" {
  description = "CRN of existing Backup & Recovery Service instance. If null, a new instance will be created."
  type        = string
  default     = null
}

##############################################################################
# Recovery Configuration
##############################################################################

variable "enable_recovery" {
  description = "Enable automatic recovery after backup completion. Set to true to test single-shot backup+recovery flow."
  type        = bool
  default     = false
}

variable "recovery_mode" {
  description = "Recovery mode: 'same-cluster' or 'cross-cluster'. Use 'cross-cluster' to test recovery to target cluster."
  type        = string
  default     = "cross-cluster"

  validation {
    condition     = contains(["same-cluster", "cross-cluster"], var.recovery_mode)
    error_message = "recovery_mode must be either 'same-cluster' or 'cross-cluster'."
  }
}

variable "wait_for_backup_completion" {
  description = "Initial wait duration before polling for backup completion. Specify with time unit suffix (e.g., '5m', '10m', '1h'). The module will then actively poll until a backup completes (up to backup_run_poll_timeout_minutes). Set to '0s' to start polling immediately."
  type        = string
  default     = "5m" # Short initial wait, then active polling takes over

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.wait_for_backup_completion))
    error_message = "wait_for_backup_completion must be a duration string with unit suffix (e.g., '5m', '10m', '1h')."
  }
}
