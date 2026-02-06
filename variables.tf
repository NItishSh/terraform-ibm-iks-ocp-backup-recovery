##############################################################################
# Cluster variables
##############################################################################

variable "cluster_id" {
  type        = string
  description = "The ID of the cluster designated for backup and recovery."
}

variable "cluster_resource_group_id" {
  type        = string
  description = "Resource group ID the cluster is deployed in."
}

variable "cluster_config_endpoint_type" {
  description = "The type of endpoint to use for the cluster config access: `default`, `private`, `vpe`, or `link`. The `default` value uses the default endpoint of the cluster."
  type        = string
  default     = "default"
  nullable    = false # use default if null is passed in
  validation {
    error_message = "Invalid endpoint type. Valid values are `default`, `private`, `vpe`, or `link`."
    condition     = contains(["default", "private", "vpe", "link"], var.cluster_config_endpoint_type)
  }
}

variable "kube_type" {
  description = "Specify the type of target cluster for the backup and recovery. Accepted values are `openshift` or `kubernetes`."
  type        = string
  default     = "openshift"

  validation {
    condition = contains([
      "openshift",
      "kubernetes",
    ], var.kube_type)
    error_message = "Accepted values are: ROKS or IKS."
  }
}

variable "wait_till" {
  description = "To avoid long wait times when you run your Terraform code, you can specify the stage when you want Terraform to mark the cluster resource creation as completed. Depending on what stage you choose, the cluster creation might not be fully completed and continues to run in the background. However, your Terraform code can continue to run without waiting for the cluster to be fully created. Supported args are `MasterNodeReady`, `OneWorkerNodeReady`, `IngressReady` and `Normal`"
  type        = string
  default     = "Normal"

  validation {
    error_message = "`wait_till` value must be one of `MasterNodeReady`, `OneWorkerNodeReady`, `IngressReady` or `Normal`."
    condition = contains([
      "MasterNodeReady",
      "OneWorkerNodeReady",
      "IngressReady",
      "Normal"
    ], var.wait_till)
  }
}

variable "wait_till_timeout" {
  description = "Timeout for wait_till in minutes."
  type        = number
  default     = 90
}

##############################################################################
# Data Source Connector (BRS)
##############################################################################

variable "add_dsc_rules_to_cluster_sg" {
  type        = bool
  description = "Set to `true` to automatically add required security group rules for the Data Source Connector and set to `false` to only register the cluster and create the policy."
  default     = true
}

variable "dsc_chart_uri" {
  description = "The full OCI registry URI for the Data Source Connector Helm chart, including the digest."
  type        = string
  default     = "oci://icr.io/ext/brs/brs-ds-connector-chart:7.2.17-release-20260108-ed857f1c@sha256:0b3e84175cb8c1b2608e99e65fc72f2d5c4264dc0a0939ad98e089cc2bb7288e"
  nullable    = false
}

variable "dsc_image_version" {
  description = "Container image for the Data Source Connector."
  type        = string
  default     = "icr.io/ext/brs/brs-ds-connector:7.2.17-release-20260108-ed857f1c@sha256:560ff2170c880dc19712e0f37ba1575240e462f5e2a2ecbc4ecb791aa471f2d0"
  nullable    = false
  validation {
    condition     = length(split("@", var.dsc_image_version)[0]) > 0
    error_message = "The image version must be in the format '<registry>/<namespace>/<repository>:<semver-tag>@sha256:<64-hex-digest>'."
  }
}

variable "dsc_name" {
  description = "Release name for the Data Source Connector Helm deployment."
  type        = string
  default     = "dsc"
  nullable    = false
}

variable "dsc_replicas" {
  description = <<-EOT
  Number of Data Source Connector podsto run.
  Recommended values:
    • 3 – for high availability across multiple nodes/zones (strongly recommended in production)
    • 1 – only for dev/test or single-node clusters
  EOT
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.dsc_replicas >= 1
    error_message = "Replicas must be at least 1."
  }
}

variable "dsc_helm_timeout" {
  description = "Timeout in seconds for the Data Source Connector Helm deployment."
  type        = number
  default     = 1500
  nullable    = false
}

variable "dsc_namespace" {
  type        = string
  description = "The cluster namespace where the Data Source Connector will be installed. Will be created if it does not exist."
  default     = "ibm-brs-data-source-connector"
  nullable    = false
}



##############################################################################
# Backup Recovery Service Instance
##############################################################################

variable "brs_endpoint_type" {
  type        = string
  description = "The endpoint type to use when connecting to the Backup and Recovery service for creating a data source connection. Allowed values are 'public' or 'private'."
  default     = "private"

  validation {
    condition     = contains(["public", "private"], var.brs_endpoint_type)
    error_message = "`endpoint_type` must be 'public' or 'private'."
  }
}

variable "registration_images" {
  type = object({
    data_mover                  = string
    velero                      = string
    velero_aws_plugin           = string
    velero_openshift_plugin     = string
    cohesity_dataprotect_plugin = string
    init_container              = optional(string, null)
  })
  default = {
    data_mover                  = "icr.io/ext/brs/cohesity-datamover:7.2.17@sha256:2b9e69f37752c6f8758b8de61b4c4ec6ccc60083d23211f59b07780069e9ddf8"
    velero                      = "icr.io/ext/brs/oadp-velero:1.3.8@sha256:2d0014471b5c0e46cf96ac452069b9fa1ebbffd1d50a8ffecb2b443dbfbd4b00"
    velero_aws_plugin           = "icr.io/ext/brs/oadp-velero-plugin-for-aws:1.3.8@sha256:3adcd0bfa963f980ad41dbff05c44c4b11d6b07e493a9c53a0ee3483a905039d"
    velero_openshift_plugin     = "icr.io/ext/brs/oadp-velero-plugin-for-openshift:1.4.7@sha256:8b5dcea0fc837e5547c253f355d71b19f825eed6fac1e19c40af44b19fd7259a"
    cohesity_dataprotect_plugin = "icr.io/ext/brs/cohesity-dataprotect-plugin:7.2.17@sha256:d7b0e02b267f27aa41c2879bb5c8dcafe9e2e6e0a825fa9e4116a7cd41403983"
  }
  description = "The images required for backup and recovery registration."
  nullable    = false
}

variable "policy" {
  type = object({
    name = string
    schedule = optional(object({
      unit      = string # Minutes, Hours, Days, Weeks, Months, Years, Runs
      frequency = number # required when unit is Minutes/Hours/Days

      # Optional extra layers (allowed even when unit = Minutes)
      minute_schedule = optional(object({ frequency = number }))
      hour_schedule   = optional(object({ frequency = number }))
      day_schedule    = optional(object({ frequency = number }))
      week_schedule   = optional(object({ day_of_week = list(string) }))
      month_schedule = optional(object({
        day_of_week   = optional(list(string))
        week_of_month = optional(string) # First, Second, Third, Fourth, Last
        day_of_month  = optional(number)
      }))
      year_schedule = optional(object({ day_of_year = string })) # First, Last
    }))

    retention = optional(object({
      duration = number
      unit     = string # Days, Weeks, Months, Years

      data_lock_config = optional(object({
        mode                           = string # Compliance, Administrative
        unit                           = string # Days, Weeks, Months, Years
        duration                       = number
        enable_worm_on_external_target = optional(bool, false)
      }))
    }))

    use_default_backup_target = optional(bool, true)
  })
  default = {
    name = "default-policy"
    schedule = {
      unit      = "Hours"
      frequency = 6
    }
    retention = {
      duration = 4
      unit     = "Weeks"
    }
    use_default_backup_target = true
  }
  validation {
    condition = contains(["Gold", "Silver", "Bronze"], var.policy.name) ? (
      var.policy.schedule == null && var.policy.retention == null
      ) : (
      var.policy.schedule != null && var.policy.retention != null
    )
    error_message = "If using built-in policies (Gold, Silver, Bronze), do not provide schedule or retention. For custom policies, both are required."
  }
  description = "The backup schedule and retentions of a Protection Policy."
}

variable "enable_auto_protect" {
  type        = bool
  description = "Enable auto-protect during the initial cluster registration. This must be set to `true` on the first run; toggling it from `false` to `true` later is not supported by the underlying API and will not retroactively create the protection group."
  default     = true
}

variable "ibmcloud_api_key" {
  type        = string
  description = "The IBM Cloud api key to generate an IAM token."
  sensitive   = true
}

variable "brs_connection_name" {
  type        = string
  description = "Name of the existing connection from the Backup & Recovery Service instance to be used for protecting the cluster."
  nullable    = false
}

variable "brs_instance_crn" {
  type        = string
  description = "CRN of the Backup & Recovery Service instance."
  nullable    = false
}
