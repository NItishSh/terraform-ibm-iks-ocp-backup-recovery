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
# Deployment Mode Control
##############################################################
variable "deployment_mode" {
  description = <<-DESC
    Deployment mode to control what components are deployed:
    - 'backup_only' (default): Registers source cluster with BRS, configures protection groups. No target cluster, no recovery.
    - 'connected_component': Registers both source + target clusters with BRS for cluster connection setup only. No backup or recovery triggered.
    - 'full_backup_recovery': End-to-end: registers clusters, triggers on-demand backup, waits for completion, executes recovery to validate.
  DESC
  type        = string
  default     = "backup_only"

  validation {
    condition     = contains(["backup_only", "connected_component", "full_backup_recovery"], var.deployment_mode)
    error_message = "`deployment_mode` must be one of 'backup_only', 'connected_component', or 'full_backup_recovery'."
  }
}

##############################################################
# Backup Related
##############################################################
variable "auto_protect_policy_name" {
  description = "Name of the existing protection policy to use for auto-protect. Required when enable_auto_protect is true and deployment_mode is 'backup_only' or 'full_backup_recovery'."
  type        = string
  default     = null

  validation {
    condition = (
      var.deployment_mode == "connected_component" ||
      var.enable_auto_protect == false ||
      (var.enable_auto_protect == true && var.auto_protect_policy_name != null)
    )
    error_message = "`auto_protect_policy_name` is required when `enable_auto_protect` is true in 'backup_only' or 'full_backup_recovery' modes."
  }
}

variable "dsc_chart_uri" {
  description = "The full OCI registry URI for the Data Source Connector Helm chart, including the digest."
  type        = string
  default     = "oci://icr.io/brs-charts/brs-ds-connector-chart:7.3.12-release-20260713-2e7241a2@sha256:b6a39948f5d1b6f765d0e73ebd2dd9c700ba0d5d5a120969efdfce2f75e8467e"
  nullable    = false
}

variable "enable_auto_protect" {
  description = "Flag to enable auto-protect for the cluster."
  type        = bool
  default     = true
  nullable    = false
}
variable "protection_groups" {
  description = "List of protection groups for granular backup control. Each group selects specific namespaces/objects and applies a policy. Use this as an alternative to `enable_auto_protect` for fine-grained control over which workloads are backed up."
  type = list(object({
    name        = string
    policy_name = string
    description = optional(string)

    # --- Kubernetes-specific params ---
    enable_indexing       = optional(bool, true)
    leverage_csi_snapshot = optional(bool, false)
    non_snapshot_backup   = optional(bool, false)
    volume_backup_failure = optional(bool, false)

    # Objects (namespaces) to protect
    objects = optional(list(object({
      id                          = optional(number)
      name                        = optional(string)
      backup_only_pvc             = optional(bool, false)
      fail_backup_on_hook_failure = optional(bool, false)
      included_resources          = optional(list(string))
      excluded_resources          = optional(list(string))
      include_pvcs = optional(list(object({
        id   = optional(number)
        name = optional(string)
      })))
      exclude_pvcs = optional(list(object({
        id   = optional(number)
        name = optional(string)
      })))

      # Per-object label-based PV/PVC inclusion
      include_params = optional(object({
        label_combination_method = optional(string, "AND") # AND, OR
        label_vector = optional(list(object({
          key   = string
          value = string
        })))
        objects = optional(list(object({}))) # usually any or map but provider says array of objects
        selected_resources = optional(list(object({
          api_group         = optional(string)
          is_cluster_scoped = optional(bool)
          kind              = optional(string)
          name              = optional(string)
          version           = optional(string)
          resource_list = optional(list(object({
            entity_id = optional(number)
            name      = optional(string)
          })))
        })))
      }))

      # Per-object label-based PV/PVC exclusion
      exclude_params = optional(object({
        label_combination_method = optional(string, "AND")
        label_vector = optional(list(object({
          key   = string
          value = string
        })))
        objects = optional(list(object({})))
        selected_resources = optional(list(object({
          api_group         = optional(string)
          is_cluster_scoped = optional(bool)
          kind              = optional(string)
          name              = optional(string)
          version           = optional(string)
          resource_list = optional(list(object({
            entity_id = optional(number)
            name      = optional(string)
          })))
        })))
      }))

      # Quiescing rules for app-consistent backups
      quiesce_groups = optional(list(object({
        quiesce_mode = string # kQuiesceTogether, kQuiesceIndependently
        quiesce_rules = list(object({
          pod_selector_labels = optional(list(object({
            key   = string
            value = string
          })))
          pre_snapshot_hooks = list(object({
            commands      = list(string)
            container     = optional(string)
            fail_on_error = optional(bool, false)
            timeout       = optional(number)
          }))
          post_snapshot_hooks = list(object({
            commands      = list(string)
            container     = optional(string)
            fail_on_error = optional(bool, false)
            timeout       = optional(number)
          }))
        }))
      })))
    })))

    # Object IDs to exclude
    exclude_object_ids = optional(list(number))

    # Label-based namespace selection (2D array of label IDs)
    label_ids         = optional(list(number))
    exclude_label_ids = optional(list(number))

    # Global label-based inclusion filter
    include_params = optional(object({
      label_combination_method = optional(string, "AND") # AND, OR
      label_vector = optional(list(object({
        key   = string
        value = string
      })))
      objects = optional(list(object({})))
      selected_resources = optional(list(object({
        api_group         = optional(string)
        is_cluster_scoped = optional(bool)
        kind              = optional(string)
        name              = optional(string)
        version           = optional(string)
        resource_list = optional(list(object({
          entity_id = optional(number)
          name      = optional(string)
        })))
      })))
    }))

    # Global label-based exclusion filter
    exclude_params = optional(object({
      label_combination_method = optional(string, "AND")
      label_vector = optional(list(object({
        key   = string
        value = string
      })))
      objects = optional(list(object({})))
      selected_resources = optional(list(object({
        api_group         = optional(string)
        is_cluster_scoped = optional(bool)
        kind              = optional(string)
        name              = optional(string)
        version           = optional(string)
        resource_list = optional(list(object({
          entity_id = optional(number)
          name      = optional(string)
        })))
      })))
    }))

    # --- Alert policy ---
    alert_policy = optional(object({
      backup_run_status = list(string) # kFailure, kSuccess, kSlaViolation, kWarning
      alert_targets = optional(list(object({
        email_address  = string
        language       = optional(string, "en-us")
        recipient_type = optional(string, "kTo")
      })))
      raise_object_level_failure_alert                    = optional(bool)
      raise_object_level_failure_alert_after_each_attempt = optional(bool)
      raise_object_level_failure_alert_after_last_attempt = optional(bool)
    }))

    # --- SLA ---
    sla = optional(list(object({
      backup_run_type = optional(string, "kIncremental") # kIncremental, kFull, kLog
      sla_minutes     = number
    })))

    # --- Scheduling ---
    start_time = optional(object({
      hour      = number
      minute    = number
      time_zone = optional(string, "America/Los_Angeles")
    }))

    # --- Advanced configs (key/value pairs) ---
    advanced_configs = optional(list(object({
      key   = string
      value = string
    })))

    priority           = optional(string, "kMedium") # kLow, kMedium, kHigh
    qos_policy         = optional(string)            # kBackupHDD, kBackupSSD, etc.
    is_paused          = optional(bool, false)
    abort_in_blackouts = optional(bool, false)
    pause_in_blackouts = optional(bool, false)
  }))
  default  = null
  nullable = true
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
  default     = 7200
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

variable "dsc_worker_pool_flavor" {
  description = "The machine flavor for the Data Source Connector worker pool. This determines the CPU, memory, and other resources available to each worker node. Common flavors: bx2.4x16 (4 vCPU, 16GB RAM), bx2.8x32 (8 vCPU, 32GB RAM), bx2.16x64 (16 vCPU, 64GB RAM)."
  type        = string
  default     = "bx2.4x16"
  nullable    = false
}

variable "dsc_pod_cpu_limits" {
  description = "CPU limit for each Data Source Connector pod (e.g., '4', '8'). Should match or exceed the worker node's available CPU."
  type        = string
  default     = "4"
  nullable    = false
}

variable "dsc_pod_memory_limits" {
  description = "Memory limit for each Data Source Connector pod (e.g., '8Gi', '16Gi'). Should match or exceed the worker node's available memory."
  type        = string
  default     = "8Gi"
  nullable    = false
}

variable "dsc_pod_cpu_requests" {
  description = "CPU request for each Data Source Connector pod (e.g., '2', '4'). This is the guaranteed CPU allocation."
  type        = string
  default     = "2"
  nullable    = false
}

variable "dsc_pod_memory_requests" {
  description = "Memory request for each Data Source Connector pod (e.g., '5Gi', '10Gi'). This is the guaranteed memory allocation."
  type        = string
  default     = "5Gi"
  nullable    = false
}

variable "dsc_image_version" {
  description = "Container image for the Data Source Connector."
  type        = string
  default     = "icr.io/ext/brs/brs-ds-connector:7.3.12-release-20260713-2e7241a2@sha256:01b4fb26764c854a141c1e3dfb3be5c1b2dc6dda397f6532fc3c84136ca0698d"
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9.-]+(/[a-z0-9._-]+)+:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$", var.dsc_image_version))
    error_message = "The image version must be in the format '<registry>/<namespace>/<repository>:<tag>@sha256:<64-hex-digest>'."
  }
}
variable "rollback_on_failure" {
  description = "Enables Helm atomic mode (--atomic) on the Data-Source Connector Helm release. When true, a failed install is automatically rolled back. WARNING: the official DSC documentation explicitly states that helm rollbacks are NOT supported for upgrades — rolling back after an upgrade may corrupt persistent state on the PVC. Set to false (recommended for production) and supervise upgrades manually."
  type        = bool
  default     = false
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
    velero_openshift_plugin     = optional(string, null)
    cohesity_dataprotect_plugin = string
    init_container              = optional(string, null)
  })
  default = {
    data_mover                  = "icr.io/ext/brs/cohesity-datamover:7.3.12@sha256:0a0e87ddce1165398390656e6ff9465815a105a79c427030f284bffbc2b7d987"
    velero                      = "icr.io/ext/brs/oadp-velero:1.5.5@sha256:386ef8dff743339a40b3b82a1fcdc9bda56c0d31a0b544acae59058d522db8d7"
    velero_aws_plugin           = "icr.io/ext/brs/oadp-velero-plugin-for-aws:1.5.5@sha256:93a7f4c514546a1d771186b8e60722d3b1632190ebc02f4a8e75e8fe0f867ced"
    velero_openshift_plugin     = "icr.io/ext/brs/oadp-velero-plugin-for-openshift:1.5.5@sha256:130894d2eca06a0e5eb49b969c03c99ed0d5a9d0cac83126e360442d438c9f2d"
    cohesity_dataprotect_plugin = "icr.io/ext/brs/cohesity-dataprotect-plugin:7.3.12@sha256:7c68cf893694f1057c700cfe223fdd86ae455889295f9f353c22d9d443170182"
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
  description = "Type of environment for the connection. Must be consistent with `kube_type` (use `kIks*` for `kubernetes`, `kRoks*` for `openshift`). Allowed values are 'kIksVpc', 'kIksClassic', 'kRoksVpc', 'kRoksClassic'."

  validation {
    condition     = contains(["kIksVpc", "kIksClassic", "kRoksVpc", "kRoksClassic"], var.connection_env_type)
    error_message = "`connection_env_type` must be 'kIksVpc', 'kIksClassic', 'kRoksVpc', or 'kRoksClassic'."
  }
}

variable "policies" {
  description = "A list of protection policies to create or look up. Set `create_new_policy` to `true` (default) to create a new policy with the specified `schedule` and `retention`. Set `create_new_policy` to `false` to reference an existing policy by `name`."
  type = list(object({
    name                      = string
    create_new_policy         = optional(bool, false)
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
    name              = "Basic"
    create_new_policy = false
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
        p.retention == null ? true : (
          p.retention.data_lock_config == null ? true :
          contains(["Compliance", "Administrative"], p.retention.data_lock_config.mode)
        )
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
        p.primary_backup_target_details == null ? true : (
          p.primary_backup_target_details.tier_settings == null ? true : alltrue([
            for ts in p.primary_backup_target_details.tier_settings : (
              (ts.cloud_platform == "AWS" ? ts.aws_tiering != null : true) &&
              (ts.cloud_platform == "Azure" ? ts.azure_tiering != null : true) &&
              (ts.cloud_platform == "Oracle" ? ts.oracle_tiering != null : true) &&
              (ts.cloud_platform == "Google" ? ts.google_tiering != null : true)
            )
          ])
        )
      )
    ])
    error_message = "The tiering configuration block must match the selected cloud_platform (e.g., provide 'aws_tiering' for 'AWS')."
  }
}


##############################################################################
# Recovery Configuration
##############################################################################

variable "recovery_type" {
  description = "Type of recovery to perform. 'same-cluster' restores to the original cluster with a namespace prefix. 'cross-cluster' restores to a different target cluster."
  type        = string
  default     = "same-cluster"
  nullable    = false

  validation {
    condition     = contains(["same-cluster", "cross-cluster"], var.recovery_type)
    error_message = "`recovery_type` must be 'same-cluster' or 'cross-cluster'."
  }
}

variable "recovery_namespace_prefix" {
  description = "Prefix to add to namespace names during recovery. For example, 'restored-' will create 'restored-myapp' from 'myapp'."
  type        = string
  default     = "restored-"
  nullable    = false
}

variable "recovery_protection_group_name" {
  description = "Name of the protection group to recover from. If null, uses the first protection group defined in the configuration."
  type        = string
  default     = null
}

variable "recovery_wait_timeout_minutes" {
  description = "Maximum time in minutes to wait for a backup to complete before triggering recovery."
  type        = number
  default     = 45
  nullable    = false

  validation {
    condition     = var.recovery_wait_timeout_minutes > 0 && var.recovery_wait_timeout_minutes <= 120
    error_message = "`recovery_wait_timeout_minutes` must be between 1 and 120 minutes."
  }
}

variable "recovery_poll_interval_seconds" {
  description = "Interval in seconds between backup status checks while waiting for backup completion."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.recovery_poll_interval_seconds >= 10 && var.recovery_poll_interval_seconds <= 300
    error_message = "`recovery_poll_interval_seconds` must be between 10 and 300 seconds."
  }
}

##############################################################################
# Cross-Cluster Recovery Configuration
##############################################################################

variable "target_cluster_id" {
  description = "Target cluster ID for cross-cluster recovery. Required when `recovery_type` is 'cross-cluster'."
  type        = string
  default     = null

  validation {
    condition     = var.recovery_type != "cross-cluster" || var.target_cluster_id != null
    error_message = "`target_cluster_id` is required when `recovery_type` is 'cross-cluster'."
  }
}

variable "target_cluster_resource_group_id" {
  description = "Target cluster resource group ID for cross-cluster recovery. Required when `recovery_type` is 'cross-cluster'."
  type        = string
  default     = null

  validation {
    condition     = var.recovery_type != "cross-cluster" || var.target_cluster_resource_group_id != null
    error_message = "`target_cluster_resource_group_id` is required when `recovery_type` is 'cross-cluster'."
  }
}

variable "target_cluster_config_endpoint_type" {
  description = "Endpoint type for target cluster config access in cross-cluster recovery. Valid values: 'default', 'private', 'vpe', 'link'."
  type        = string
  default     = "private"
  nullable    = false

  validation {
    condition     = contains(["default", "private", "vpe", "link"], var.target_cluster_config_endpoint_type)
    error_message = "`target_cluster_config_endpoint_type` must be 'default', 'private', 'vpe', or 'link'."
  }
}

variable "target_brs_connection_name" {
  description = "Name for the BRS connection to the target cluster in cross-cluster recovery or connected component setup. If null, defaults to '{cluster_id}-target-connection'."
  type        = string
  default     = null
}

variable "target_brs_create_new_connection" {
  description = "Whether to create a new BRS connection for the target cluster. Set to `false` to reuse an existing connection matching `target_brs_connection_name`. Defaults to `true`."
  type        = bool
  default     = true
  nullable    = false
}

variable "target_create_dsc_worker_pool" {
  description = "Create dedicated worker pool for Data Source Connector on target cluster in cross-cluster recovery."
  type        = bool
  default     = true
  nullable    = false
}
