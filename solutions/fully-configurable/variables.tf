########################################################################################################################
# Input variables
########################################################################################################################

variable "ibmcloud_api_key" {
  type        = string
  description = "The IBM Cloud API key."
  sensitive   = true
}

variable "provider_visibility" {
  description = "Set the visibility value for the IBM terraform provider. Supported values are `public`, `private`, `public-and-private`. [Learn more](https://registry.terraform.io/providers/IBM-Cloud/ibm/latest/docs/guides/custom-service-endpoints)."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["public", "private", "public-and-private"], var.provider_visibility)
    error_message = "Invalid visibility option. Allowed values are 'public', 'private', or 'public-and-private'."
  }
}
##############################################################################
# Cluster variables
##############################################################################

variable "cluster_id" {
  type        = string
  description = "The ID of the cluster to deploy the agents in."
}

variable "cluster_resource_group_id" {
  type        = string
  description = "The resource group ID of the cluster."
}

variable "cluster_config_endpoint_type" {
  description = "The type of endpoint to use for the cluster config access: `default`, `private`, `vpe`, or `link`. The `default` value uses the default endpoint of the cluster."
  type        = string
  default     = "private"
  nullable    = false # use default if null is passed in
  validation {
    error_message = "Invalid endpoint type. Valid values are `default`, `private`, `vpe`, or `link`."
    condition     = contains(["default", "private", "vpe", "link"], var.cluster_config_endpoint_type)
  }
}

variable "wait_till" {
  description = "To avoid long wait times when you run your Terraform code, you can specify the stage when you want Terraform to mark the cluster resource creation as completed. Depending on what stage you choose, the cluster creation might not be fully completed and continues to run in the background. However, your Terraform code can continue to run without waiting for the cluster to be fully created. Supported args are `MasterNodeReady`, `OneWorkerNodeReady`, `IngressReady` and `Normal`."
  type        = string
  default     = "Normal"
}

variable "wait_till_timeout" {
  description = "Timeout for wait_till in minutes."
  type        = number
  default     = 90
}

##############################################################
# Backup Related
##############################################################
variable "auto_protect_policy_name" {
  description = "Name of the existing protection policy to use for auto-protect. Required when enable_auto_protect is true."
  type        = string
  default     = null
}

variable "dsc_chart_uri" {
  description = "The full OCI registry URI for the Data Source Connector Helm chart, including the digest."
  type        = string
  default     = "oci://icr.io/ext/brs/brs-ds-connector-chart:7.2.18-release-20260226-49768040@sha256:99728a3146a7d8b2ae2f88300a6a89752488d3733e29118ee83a655959114541"
  nullable    = false
}

variable "enable_auto_protect" {
  description = "Flag to enable auto-protect for the cluster."
  type        = bool
  default     = true
  nullable    = false
}

variable "dsc_namespace" {
  description = "The namespace in the cluster where the Data Source Connector will be deployed."
  type        = string
  default     = "ibm-brs-data-source-connector"
  nullable    = false
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
  default     = 3
  nullable    = false
}

variable "dsc_helm_timeout" {
  description = "Timeout in seconds for the Data Source Connector Helm deployment."
  type        = number
  default     = 1500
  nullable    = false
}

variable "dsc_storage_class" {
  type        = string
  description = "Storage class to use for the Data Source Connector persistent volume. By default, it uses 'ibmc-vpc-block-metro-5iops-tier' for VPC clusters and 'ibmc-block-silver' for Classic clusters."
  default     = "ibmc-vpc-block-metro-5iops-tier"
}

variable "create_dsc_worker_pool" {
  description = "Set to `true` to create a dedicated worker pool for the Data Source Connector in VPC clusters. If set to `false`, the connector will be deployed on existing worker nodes."
  type        = bool
  default     = true
}

variable "dsc_image_version" {
  description = "Container image for the Data Source Connector."
  type        = string
  default     = "icr.io/ext/brs/brs-ds-connector:7.2.18-release-20260226-49768040@sha256:99728a3146a7d8b2ae2f88300a6a89752488d3733e29118ee83a655959114541"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9.-]+(/[a-z0-9._-]+)+:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$", var.dsc_image_version))
    error_message = "The image version must be in the format '<registry>/<namespace>/<repository>:<tag>@sha256:<64-hex-digest>'."
  }
}
variable "dsc_registry" {
  description = "Registry for the Data Source Connector."
  type        = string
  default     = "icr.io"
  nullable    = false
}
variable "brs_connection_name" {
  type        = string
  description = "Name of the connection from the Backup & Recovery Service instance to be used for protecting the cluster. If `brs_create_new_connection` is set to `true` (default), this will be the name of the new connection created. If set to `false`, this must be the name of an existing connection."
  nullable    = false
}

variable "existing_brs_instance_crn" {
  type        = string
  description = "CRN of the Backup & Recovery Service instance."
  default     = null
}

variable "add_dsc_rules_to_cluster_sg" {
  type        = bool
  description = "Set to `true` to automatically add the security group rules required by the Data Source Connector. This is mandatory when registering the cluster via its public service endpoint. Set to `false` to only register the cluster and create the policy without modifying security groups."
  default     = false
}

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
    data_mover                  = "icr.io/ext/brs/cohesity-datamover:7.2.18@sha256:f347698eb6180645d8c1b71d69a9fc40bb7c0bd14e5cdece9b7da79af74e8262"
    velero                      = "icr.io/ext/brs/oadp-velero:1.3.8@sha256:2d0014471b5c0e46cf96ac452069b9fa1ebbffd1d50a8ffecb2b443dbfbd4b00"
    velero_aws_plugin           = "icr.io/ext/brs/oadp-velero-plugin-for-aws:1.3.8@sha256:3adcd0bfa963f980ad41dbff05c44c4b11d6b07e493a9c53a0ee3483a905039d"
    velero_openshift_plugin     = "icr.io/ext/brs/oadp-velero-plugin-for-openshift:1.4.7@sha256:8b5dcea0fc837e5547c253f355d71b19f825eed6fac1e19c40af44b19fd7259a"
    cohesity_dataprotect_plugin = "icr.io/ext/brs/cohesity-dataprotect-plugin:7.2.18@sha256:629fdf6852a9583674c41fc1ccbab3006c737067f5dccafbee2fe36fbc6ee748"
  }
  description = "The images required for backup and recovery registration."
  nullable    = false
}

variable "kube_type" {
  type        = string
  description = "Type of Kubernetes cluster. Allowed values are 'kubernetes' or 'openshift'."
  default     = "kubernetes"

  validation {
    condition     = contains(["kubernetes", "openshift"], var.kube_type)
    error_message = "`kube_type` must be 'kubernetes' or 'openshift'."
  }
}

variable "brs_instance_name" {
  type        = string
  description = "Name of the Backup & Recovery Service instance. Required only when `existing_brs_instance_crn` is not provided."
  default     = null

  validation {
    condition     = var.existing_brs_instance_crn != null || var.brs_instance_name != null
    error_message = "`brs_instance_name` is required when `existing_brs_instance_crn` is not provided."
  }
}

variable "brs_create_new_connection" {
  type        = bool
  description = "Flag to create a new connection from the Backup & Recovery Service instance to the cluster. When set to `true` (default), a new connection is created with the name specified in `brs_connection_name`. When `false`, it uses an existing connection matching `brs_connection_name`."
  default     = true
  nullable    = false
}

variable "region" {
  type        = string
  description = "Region of the Backup & Recovery Service instance. Required only when `existing_brs_instance_crn` is not provided."
  default     = null

  validation {
    condition     = var.existing_brs_instance_crn != null || var.region != null
    error_message = "`region` is required when `existing_brs_instance_crn` is not provided."
  }
}

variable "resource_tags" {
  type        = list(string)
  description = "Add user resource tags to the Backup Recovery instance to organize, track, and manage costs."
  default     = []
}

variable "access_tags" {
  type        = list(string)
  description = "Add existing access management tags to the Backup Recovery instance to manage access."
  default     = []
}

variable "connection_env_type" {
  type        = string
  description = "Type of environment for the connection. Allowed values are 'kIksVpc', 'kIksClassic', 'kRoksVpc', 'kRoksClassic'."
  default     = "kRoksVpc"

  validation {
    condition     = contains(["kIksVpc", "kIksClassic", "kRoksVpc", "kRoksClassic"], var.connection_env_type)
    error_message = "`connection_env_type` must be 'kIksVpc', 'kIksClassic', 'kRoksVpc', or 'kRoksClassic'."
  }
}
variable "policies" {
  description = "A list of protection policies to create or look up. Set `create_new_policy` to `true` (default) to create a new policy with the specified `schedule` and `retention`. Set `create_new_policy` to `false` to reference an existing policy by `name`."
  type = list(object({
    name                      = string
    create_new_policy         = optional(bool, true)
    use_default_backup_target = optional(bool, true)

    # --- primary_backup_target advanced details ---
    primary_backup_target_details = optional(object({
      target_id = number
      tier_settings = optional(list(object({
        cloud_platform = string # AWS, Azure, Google, Oracle
        aws_tiering = optional(object({
          tiers = list(object({ tier_type = string, move_after = number, move_after_unit = string }))
        }))
        azure_tiering = optional(object({
          tiers = list(object({ tier_type = string, move_after = number, move_after_unit = string }))
        }))
        google_tiering = optional(object({
          tiers = list(object({ tier_type = string, move_after = number, move_after_unit = string }))
        }))
        oracle_tiering = optional(object({
          tiers = list(object({ tier_type = string, move_after = number, move_after_unit = string }))
        }))
      })))
    }))

    # --- Standard backup schedule and retention ---
    schedule = optional(object({
      unit            = string
      minute_schedule = optional(object({ frequency = number }))
      hour_schedule   = optional(object({ frequency = number }))
      day_schedule    = optional(object({ frequency = number }))
      week_schedule   = optional(object({ day_of_week = list(string) }))
      month_schedule  = optional(object({ day_of_month = optional(number), day_of_week = optional(list(string)), week_of_month = optional(string) }))
      year_schedule   = optional(object({ day_of_year = string }))
    }))
    retention = optional(object({
      duration         = number
      unit             = string
      data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
    }))

    # --- Bare Metal Recovery (BMR) ---
    bmr = optional(object({
      schedule = optional(object({
        unit            = string
        minute_schedule = optional(object({ frequency = number }))
        hour_schedule   = optional(object({ frequency = number }))
        day_schedule    = optional(object({ frequency = number }))
        week_schedule   = optional(object({ day_of_week = list(string) }))
        month_schedule  = optional(object({ day_of_month = optional(number), day_of_week = optional(list(string)), week_of_month = optional(string) }))
        year_schedule   = optional(object({ day_of_year = string }))
      }))
      retention = object({
        duration         = number
        unit             = string
        data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
      })
    }))

    # --- Continuous Data Protection (CDP) ---
    cdp = optional(object({
      retention = object({
        duration         = number
        unit             = string
        data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
      })
    }))

    # --- Database Log Backup ---
    log = optional(object({
      schedule = object({
        unit            = string
        minute_schedule = optional(object({ frequency = number }))
        hour_schedule   = optional(object({ frequency = number }))
        day_schedule    = optional(object({ frequency = number }))
        week_schedule   = optional(object({ day_of_week = list(string) }))
        month_schedule  = optional(object({ day_of_month = optional(number), day_of_week = optional(list(string)), week_of_month = optional(string) }))
        year_schedule   = optional(object({ day_of_year = string }))
      })
      retention = object({
        duration         = number
        unit             = string
        data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
      })
    }))

    # --- Storage Array Snapshot ---
    storage_array_snapshot = optional(object({
      schedule = object({
        unit            = string
        minute_schedule = optional(object({ frequency = number }))
        hour_schedule   = optional(object({ frequency = number }))
        day_schedule    = optional(object({ frequency = number }))
        week_schedule   = optional(object({ day_of_week = list(string) }))
        month_schedule  = optional(object({ day_of_month = optional(number), day_of_week = optional(list(string)), week_of_month = optional(string) }))
        year_schedule   = optional(object({ day_of_year = string }))
      })
      retention = object({
        duration         = number
        unit             = string
        data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
      })
    }))

    # --- Blackout windows ---
    blackout_window = optional(list(object({
      day = string
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
      backup_type  = optional(string, "kRegular")
    })))

    # --- Extended retention (keep certain snapshots longer) ---
    extended_retention = optional(list(object({
      schedule = object({
        unit      = string
        frequency = number
      })
      retention = object({
        duration = number
        unit     = string
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

    # --- Cascaded Targets Config ---
    cascaded_targets_config = optional(object({
      source_cluster_id = number
      remote_targets = list(object({
        archival_targets = optional(list(object({
          target_id           = number
          backup_run_type     = optional(string)
          config_id           = optional(string)
          copy_on_run_success = optional(bool)
          schedule = object({
            unit      = string
            frequency = optional(number)
          })
          retention = object({
            duration         = number
            unit             = string
            data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
          })
          extended_retention = optional(list(object({
            schedule = object({
              unit      = string
              frequency = number
            })
            retention = object({
              duration         = number
              unit             = string
              data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
            })
            run_type  = optional(string, "Regular")
            config_id = optional(string)
          })))
        })))
        cloud_spin_targets = optional(list(object({
          target = object({
            id = optional(number)
          })
          backup_run_type     = optional(string)
          config_id           = optional(string)
          copy_on_run_success = optional(bool)
          schedule = object({
            unit      = string
            frequency = optional(number)
          })
          retention = object({
            duration         = number
            unit             = string
            data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
          })
          extended_retention = optional(list(object({
            schedule = object({
              unit      = string
              frequency = number
            })
            retention = object({
              duration         = number
              unit             = string
              data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
            })
            run_type  = optional(string, "Regular")
            config_id = optional(string)
          })))
        })))
        replication_targets = optional(list(object({
          target_type         = string
          target_id           = number
          backup_run_type     = optional(string)
          config_id           = optional(string)
          copy_on_run_success = optional(bool)
          schedule = object({
            unit      = string
            frequency = optional(number)
          })
          retention = object({
            duration         = number
            unit             = string
            data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
          })
          extended_retention = optional(list(object({
            schedule = object({
              unit      = string
              frequency = number
            })
            retention = object({
              duration         = number
              unit             = string
              data_lock_config = optional(object({ mode = string, unit = string, duration = number, enable_worm_on_external_target = optional(bool, false) }))
            })
            run_type  = optional(string, "Regular")
            config_id = optional(string)
          })))
        })))
      }))
    }))
  }))
  default = [{
    name = "basic-policy"
    schedule = {
      unit         = "Days"
      day_schedule = { frequency = 1 }
    }
    retention = {
      duration = 2
      unit     = "Days"
    }
  }]

  # 1. Structural Validation
  validation {
    condition = alltrue([
      for p in var.policies : (
        p.create_new_policy == false ||
        (p.schedule != null && p.retention != null)
      )
    ])
    error_message = "When create_new_policy is true, both schedule and retention are required."
  }

  # 2. Unit Enumerations (Registry Constraint: "Allowable values: Days, Weeks, Months, Years")
  validation {
    condition = alltrue([
      for p in var.policies : p.retention == null ? true :
      contains(["Days", "Weeks", "Months", "Years"], p.retention.unit)
    ])
    error_message = "Retention unit must be one of: Days, Weeks, Months, Years."
  }

  # 3. Frequency Minimums (Registry/Cohesity Constraint: Minutes >= 7, Others >= 1)
  validation {
    condition = alltrue([
      for p in var.policies : p.schedule == null ? true : (
        (p.schedule.minute_schedule == null ? true : p.schedule.minute_schedule.frequency >= 7) &&
        (p.schedule.hour_schedule == null ? true : p.schedule.hour_schedule.frequency >= 1) &&
        (p.schedule.day_schedule == null ? true : p.schedule.day_schedule.frequency >= 1)
      )
    ])
    error_message = "Invalid frequency: Minutes must be >= 7. Hours and Days must be >= 1."
  }

  # 4. Data Lock (WORM) Modes (Registry Constraint: "Compliance" or "Administrative")
  validation {
    condition = alltrue([
      for p in var.policies : (
        p.retention == null || p.retention.data_lock_config == null ? true :
        contains(["Compliance", "Administrative"], p.retention.data_lock_config.mode)
      )
    ])
    error_message = "Data lock mode must be 'Compliance' or 'Administrative'."
  }

  # 5. Blackout Window Weekdays (Registry Constraint: Proper case day names)
  validation {
    condition = alltrue([
      for p in var.policies : p.blackout_window == null ? true : alltrue([
        for bw in p.blackout_window :
        contains(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"], bw.day)
      ])
    ])
    error_message = "Blackout window 'day' must be the full weekday name (e.g., 'Monday')."
  }

  # 6. Run Timeouts Backup Types (Registry Constraint: kRegular, kFull, kLog, kSystem)
  validation {
    condition = alltrue([
      for p in var.policies : p.run_timeouts == null ? true : alltrue([
        for rt in p.run_timeouts :
        contains(["kRegular", "kFull", "kLog", "kSystem", "kHydrateCDP", "kStorageArraySnapshot"], rt.backup_type)
      ])
    ])
    error_message = "Invalid backup_type in run_timeouts. Allowed: kRegular, kFull, kLog, kSystem, kHydrateCDP, kStorageArraySnapshot."
  }

  # 7. Tiering Platform Cross-Check
  # Ensures user doesn't provide azure_tiering when cloud_platform is "AWS"
  validation {
    condition = alltrue([
      for p in var.policies : (
        p.primary_backup_target_details == null || p.primary_backup_target_details.tier_settings == null ? true : alltrue([
          for ts in p.primary_backup_target_details.tier_settings : (
            (ts.cloud_platform == "AWS" ? ts.aws_tiering != null : true) &&
            (ts.cloud_platform == "Azure" ? ts.azure_tiering != null : true) &&
            (ts.cloud_platform == "Oracle" ? ts.oracle_tiering != null : true) &&
            (ts.cloud_platform == "Google" ? ts.google_tiering != null : true)
          )
        ])
      )
    ])
    error_message = "The tiering configuration block must match the selected cloud_platform (e.g., provide 'aws_tiering' for 'AWS')."
  }
}
