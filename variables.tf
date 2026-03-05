##############################################################################
# Cluster variables
##############################################################################

variable "cluster_id" {
  description = "The ID of the cluster designated for backup and recovery."
  type        = string
}

variable "cluster_resource_group_id" {
  description = "Resource group ID the cluster is deployed in."
  type        = string
}

variable "cluster_config_endpoint_type" {
  description = "The type of endpoint to use for the cluster config access: `default`, `private`, `vpe`, or `link`. The `default` value uses the default endpoint of the cluster."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "private", "vpe", "link"], var.cluster_config_endpoint_type)
    error_message = "Invalid endpoint type. Valid values are `default`, `private`, `vpe`, or `link`."
  }

  nullable = false
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
    condition = contains([
      "MasterNodeReady",
      "OneWorkerNodeReady",
      "IngressReady",
      "Normal"
    ], var.wait_till)
    error_message = "`wait_till` value must be one of `MasterNodeReady`, `OneWorkerNodeReady`, `IngressReady` or `Normal`."
  }
}

variable "wait_till_timeout" {
  description = "Timeout for wait_till in minutes."
  type        = number
  default     = 90
}

##############################################################################
# Data Source Connector (DSC)
##############################################################################

variable "add_dsc_rules_to_cluster_sg" {
  description = "Set to `true` to automatically add the security group rules required by the Data Source Connector. This is mandatory when registering the cluster via its public service endpoint. Set to `false` to only register the cluster and create the policy without modifying security groups."
  type        = bool
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

  validation {
    condition     = can(regex("^[a-z0-9.-]+(/[a-z0-9._-]+)+:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$", var.dsc_image_version))
    error_message = "The image version must be in the format '<registry>/<namespace>/<repository>:<tag>@sha256:<64-hex-digest>'."
  }

  nullable = false
}

variable "dsc_name" {
  description = "Release name for the Data Source Connector Helm deployment."
  type        = string
  default     = "dsc"
  nullable    = false
}

variable "dsc_replicas" {
  description = <<-EOT
  Number of Data Source Connector pods to run.
  Recommended values:
    • 3 – for high availability across multiple nodes/zones (strongly recommended in production)
    • 1 – only for dev/test or single-node clusters
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.dsc_replicas >= 1
    error_message = "Replicas must be at least 1."
  }

  nullable = false
}

variable "dsc_helm_timeout" {
  description = "Timeout in seconds for the Data Source Connector Helm deployment."
  type        = number
  default     = 1500
  nullable    = false
}

variable "dsc_namespace" {
  description = "The cluster namespace where the Data Source Connector will be installed. Will be created if it does not exist."
  type        = string
  default     = "ibm-brs-data-source-connector"
  nullable    = false
}

variable "dsc_storage_class" {
  description = "Storage class to use for the Data Source Connector persistent volume. By default, it uses 'ibmc-vpc-block-metro-5iops-tier' for VPC clusters and 'ibmc-block-silver' for Classic clusters."
  type        = string
  default     = null
}

variable "create_dsc_worker_pool" {
  description = "Set to `true` to create a dedicated worker pool for the Data Source Connector in VPC clusters. If set to `false`, the connector will be deployed on existing worker nodes."
  type        = bool
  default     = true
}

##############################################################################
# Backup Recovery Service Instance
##############################################################################

variable "ibmcloud_api_key" {
  description = "The IBM Cloud api key to generate an IAM token."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region where the Backup & Recovery Service instance needs to be created."
  type        = string
  default     = null
  validation {
    condition     = var.existing_brs_instance_crn != null || var.region != null
    error_message = "`region` is required when `existing_brs_instance_crn` is not provided."
  }
}

variable "brs_endpoint_type" {
  description = "The endpoint type to use when connecting to the Backup and Recovery service for creating a data source connection. Allowed values are 'public' or 'private'."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["public", "private"], var.brs_endpoint_type)
    error_message = "`endpoint_type` must be 'public' or 'private'."
  }
}

variable "existing_brs_instance_crn" {
  description = "CRN of the Backup & Recovery Service instance."
  type        = string
  default     = null

  validation {
    condition     = var.existing_brs_instance_crn == null || can(regex("^crn:v1:[a-z0-9-]+:[a-z0-9-]*:[a-z0-9-]+:[a-z0-9-]*:a/[a-f0-9]+:[a-f0-9-]+::$", var.existing_brs_instance_crn))
    error_message = "'existing_brs_instance_crn' must be a valid CRN. Example: crn:v1:bluemix:public:backup-recovery:<region>:a/<account-id>:<instance-guid>::"
  }
}

variable "brs_instance_name" {
  description = "Name of the Backup & Recovery Service instance. Required only when `existing_brs_instance_crn` is not provided."
  type        = string
  default     = null

  validation {
    condition     = var.brs_instance_name == null || var.brs_instance_name != ""
    error_message = "'brs_instance_name' must not be an empty string. Either provide a valid name or leave it as null."
  }
  validation {
    condition     = var.existing_brs_instance_crn != null || var.brs_instance_name != null
    error_message = "`brs_instance_name` is required when `existing_brs_instance_crn` is not provided."
  }
}

variable "brs_connection_name" {
  description = "Name of the connection from the Backup & Recovery Service instance to be used for protecting the cluster. If `brs_create_new_connection` is set to `true` (default), this will be the name of the new connection created. If set to `false`, this must be the name of an existing connection."
  type        = string
  nullable    = false

  validation {
    condition     = var.brs_connection_name != ""
    error_message = "'brs_connection_name' must not be an empty string."
  }
}

variable "brs_create_new_connection" {
  description = "Flag to create a new connection from the Backup & Recovery Service instance to the cluster. When set to `true` (default), a new connection is created with the name specified in `brs_connection_name`. When `false`, it uses an existing connection matching `brs_connection_name`."
  type        = bool
  default     = true
}

variable "connection_env_type" {
  description = "Connection environment type to determine the required parameters for creating a new connection. Allowed values are 'kIksVpc', 'kRoksVpc', 'kRoksClassic', and 'kIksClassic'."
  type        = string
  default     = "kIksVpc"

  validation {
    condition     = contains(["kIksVpc", "kRoksVpc", "kRoksClassic", "kIksClassic"], var.connection_env_type)
    error_message = "`connection_env_type` must be one of 'kIksVpc', 'kRoksVpc', 'kRoksClassic', or 'kIksClassic'."
  }
}

##############################################################################
# Protection Policy
##############################################################################

variable "policy" {
  description = "The backup schedule and retentions of a Protection Policy."
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

    # --- Full backup schedule (periodic full backups on top of incrementals) ---
    full_schedule = optional(object({
      unit          = string # Days, Weeks, Months, Years, ProtectOnce
      day_schedule  = optional(object({ frequency = number }))
      week_schedule = optional(object({ day_of_week = list(string) }))
      month_schedule = optional(object({
        day_of_week   = optional(list(string))
        week_of_month = optional(string)
        day_of_month  = optional(number)
      }))
      year_schedule = optional(object({ day_of_year = string }))

      retention = object({
        duration = number
        unit     = string # Days, Weeks, Months, Years
        data_lock_config = optional(object({
          mode                           = string
          unit                           = string
          duration                       = number
          enable_worm_on_external_target = optional(bool, false)
        }))
      })
    }))

    # --- Blackout windows (time windows when backups should not run) ---
    blackout_window = optional(list(object({
      day = string # Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday
      start_time = object({
        hour      = number
        minute    = number
        time_zone = optional(string, "America/New_York")
      })
      end_time = object({
        hour      = number
        minute    = number
        time_zone = optional(string, "America/New_York")
      })
    })))

    # --- Run timeouts (prevent hung backup jobs) ---
    run_timeouts = optional(list(object({
      timeout_mins = number
      backup_type  = optional(string, "kRegular") # kRegular, kFull, kLog, kSystem, kHydrateCDP, kStorageArraySnapshot
    })))

    # --- Extended retention (keep certain snapshots longer) ---
    extended_retention = optional(list(object({
      schedule = object({
        unit      = string # Runs, Days, Weeks, Months, Years
        frequency = number
      })
      retention = object({
        duration = number
        unit     = string # Days, Weeks, Months, Years
        data_lock_config = optional(object({
          mode                           = string
          unit                           = string
          duration                       = number
          enable_worm_on_external_target = optional(bool, false)
        }))
      })
      run_type  = optional(string, "Regular")
      config_id = optional(string)
    })))
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
    condition = (
      (var.policy.schedule == null && var.policy.retention == null) ||
      (var.policy.schedule != null && var.policy.retention != null)
    )
    error_message = "For existing policies, do not provide schedule or retention (both must be null). For custom policies, both schedule and retention are required."
  }
}

variable "enable_auto_protect" {
  description = "Enable auto-protect during the initial cluster registration. This must be set to `true` on the first run; toggling it from `false` to `true` later is not supported by the underlying API and will not retroactively create the protection group."
  type        = bool
  default     = true
}

##############################################################################
# Registration Images
##############################################################################

variable "registration_images" {
  description = "The images required for backup and recovery registration."
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
  nullable = false
}

##############################################################################
# Resource Tags
##############################################################################

variable "resource_tags" {
  description = "Add user resource tags to the Backup Recovery instance to organize, track, and manage costs."
  type        = list(string)
  default     = []
}

variable "access_tags" {
  description = "Add existing access management tags to the Backup Recovery instance to manage access."
  type        = list(string)
  default     = []
}
