##############################################################################
# Cluster variables
##############################################################################

variable "cluster_id" {
  description = "The ID of the cluster designated for backup and recovery."
  type        = string
}

variable "add_cluster_tags" {
  description = "Whether to add BRS tags to the cluster. Set to false if you manage cluster tags externally to avoid drift. When false, you should manually add the tags 'brs-region:<region>' and 'brs-guid:<guid>' to your cluster."
  type        = bool
  default     = true
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

variable "rollback_on_failure" {
  description = "Flag to automatically rollback the helm chart on installation failure."
  type        = bool
  default     = true
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

variable "install_required_binaries" {
  type        = bool
  default     = true
  description = "When set to true, a script will run to check if `kubectl` and `jq`, `IBM Cloud CLI (ibmcloud)`, and the `backup-recovery plugin` exist on the runtime and if not attempt to download them from the public internet and install them to /tmp. Set to false to skip running this script."
  nullable    = false
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
  default     = "oci://icr.io/ext/brs/brs-ds-connector-chart:7.2.18-release-20260226-49768040@sha256:99728a3146a7d8b2ae2f88300a6a89752488d3733e29118ee83a655959114541"
  nullable    = false
}

variable "dsc_image_version" {
  description = "Container image for the Data Source Connector."
  type        = string
  default     = "icr.io/ext/brs/brs-ds-connector:7.2.18-release-20260226-49768040@sha256:99728a3146a7d8b2ae2f88300a6a89752488d3733e29118ee83a655959114541"

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

variable "auto_protect_policy_name" {
  description = "Name of an existing protection policy to use for auto-protect. Required when `enable_auto_protect` is `true`. The policy must already exist in the BRS instance (create it using the `terraform-ibm-backup-recovery` module)."
  type        = string
  default     = null

  validation {
    condition     = var.enable_auto_protect == false || (var.enable_auto_protect == true && var.auto_protect_policy_name != null)
    error_message = "auto_protect_policy_name is required when enable_auto_protect is true."
  }
}

variable "enable_auto_protect" {
  description = "Enable auto-protect during the initial cluster registration. This must be set to `true` on the first run; toggling it from `false` to `true` later is not supported by the underlying API and will not retroactively create the protection group."
  type        = bool
  default     = true
}

##############################################################################
# Protection Groups (granular backup control)
##############################################################################

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
  default  = []
  nullable = false
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
    data_mover                  = "icr.io/ext/brs/cohesity-datamover:7.2.18@sha256:f347698eb6180645d8c1b71d69a9fc40bb7c0bd14e5cdece9b7da79af74e8262"
    velero                      = "icr.io/ext/brs/oadp-velero:1.3.8@sha256:2d0014471b5c0e46cf96ac452069b9fa1ebbffd1d50a8ffecb2b443dbfbd4b00"
    velero_aws_plugin           = "icr.io/ext/brs/oadp-velero-plugin-for-aws:1.3.8@sha256:3adcd0bfa963f980ad41dbff05c44c4b11d6b07e493a9c53a0ee3483a905039d"
    velero_openshift_plugin     = "icr.io/ext/brs/oadp-velero-plugin-for-openshift:1.4.7@sha256:8b5dcea0fc837e5547c253f355d71b19f825eed6fac1e19c40af44b19fd7259a"
    cohesity_dataprotect_plugin = "icr.io/ext/brs/cohesity-dataprotect-plugin:7.2.18@sha256:629fdf6852a9583674c41fc1ccbab3006c737067f5dccafbee2fe36fbc6ee748"
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

##############################################################################
# BRS Policy Variables
##############################################################################

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
  default = null

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
# Recovery Variables
##############################################################################

variable "recoveries" {
  description = "List of recovery operations to restore backups created by protection groups. Supports multiple environments: Kubernetes, VMware, Physical, AWS, Azure, GCP, SQL, Oracle, and more. This variable follows the official IBM Backup Recovery provider schema and can be used across different backup scenarios. For IKS/ROKS recovery, use kubernetes_params. See the Usage section in the README for examples."
  type = list(object({
    name                 = string
    snapshot_environment = string # kKubernetes, kVMware, kPhysical, kAWS, kAzure, kGCP, kSQL, kOracle, kView, etc.

    # Kubernetes-specific recovery parameters
    kubernetes_params = optional(object({
      recovery_action = string # RecoverNamespaces, RecoverPVs, RecoverApps

      objects = list(object({
        snapshot_id           = string
        point_in_time_usecs   = optional(number)
        protection_group_id   = optional(string)
        protection_group_name = optional(string)
        recover_from_standby  = optional(bool, false)
      }))
    }))

    # VMware-specific recovery parameters (for future provider support)
    vmware_params = optional(object({
      recovery_action = optional(string)
      objects = optional(list(object({
        snapshot_id           = optional(string)
        point_in_time_usecs   = optional(number)
        protection_group_id   = optional(string)
        protection_group_name = optional(string)
        recover_from_standby  = optional(bool, false)
      })))
    }))

    # Physical server recovery parameters (for future provider support)
    physical_params = optional(object({
      recovery_action = optional(string)
      objects = optional(list(object({
        snapshot_id           = optional(string)
        point_in_time_usecs   = optional(number)
        protection_group_id   = optional(string)
        protection_group_name = optional(string)
      })))
    }))

    # AWS-specific recovery parameters (for future provider support)
    aws_params = optional(object({
      recovery_action = optional(string)
      objects = optional(list(object({
        snapshot_id           = optional(string)
        point_in_time_usecs   = optional(number)
        protection_group_id   = optional(string)
        protection_group_name = optional(string)
      })))
    }))

    # Azure-specific recovery parameters (for future provider support)
    azure_params = optional(object({
      recovery_action = optional(string)
      objects = optional(list(object({
        snapshot_id           = optional(string)
        point_in_time_usecs   = optional(number)
        protection_group_id   = optional(string)
        protection_group_name = optional(string)
      })))
    }))

    # GCP-specific recovery parameters (for future provider support)
    gcp_params = optional(object({
      recovery_action = optional(string)
      objects = optional(list(object({
        snapshot_id           = optional(string)
        point_in_time_usecs   = optional(number)
        protection_group_id   = optional(string)
        protection_group_name = optional(string)
      })))
    }))

    # SQL-specific recovery parameters (for future provider support)
    sql_params = optional(object({
      recovery_action = optional(string)
      objects = optional(list(object({
        snapshot_id           = optional(string)
        point_in_time_usecs   = optional(number)
        protection_group_id   = optional(string)
        protection_group_name = optional(string)
      })))
    }))

    # Oracle-specific recovery parameters (for future provider support)
    oracle_params = optional(object({
      recovery_action = optional(string)
      objects = optional(list(object({
        snapshot_id           = optional(string)
        point_in_time_usecs   = optional(number)
        protection_group_id   = optional(string)
        protection_group_name = optional(string)
      })))
    }))
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for r in var.recoveries : contains([
        "kKubernetes", "kVMware", "kPhysical", "kAWS", "kAzure",
        "kGCP", "kSQL", "kOracle", "kView", "kPuppeteer",
        "kPhysicalFiles", "kPure", "kNimble", "kAzureNative",
        "kAD", "kAWSNative", "kGCPNative", "kKVM", "kAcropolis",
        "kExchange", "kHyperV", "kHyperVVSS", "kO365", "kO365Outlook",
        "kO365PublicFolders", "kO365Teams", "kO365Group", "kO365Exchange",
        "kO365OneDrive", "kO365Sharepoint", "kCassandra", "kMongoDB",
        "kCouchbase", "kHdfs", "kHive", "kHBase", "kUDA", "kSfdc"
      ], r.snapshot_environment)
    ])
    error_message = "snapshot_environment must be a valid environment type as per IBM Backup Recovery provider documentation."
  }
}
