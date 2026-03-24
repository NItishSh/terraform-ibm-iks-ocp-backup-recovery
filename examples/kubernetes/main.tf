locals {
  default_version = data.ibm_container_cluster_versions.cluster_versions.default_kube_version
  cluster_id      = var.cluster_name_id != null ? (var.classic_cluster ? data.ibm_container_cluster.classic_cluster_data[0].id : data.ibm_container_vpc_cluster.vpc_cluster_data[0].id) : (var.classic_cluster ? ibm_container_cluster.classic_cluster[0].id : ibm_container_vpc_cluster.vpc_cluster[0].id)
}
##############################################################################
# Resource Group
##############################################################################

module "resource_group" {
  source                       = "terraform-ibm-modules/resource-group/ibm"
  version                      = "1.4.8"
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

########################################################################################################################
# VPC + Subnet + Public Gateway
########################################################################################################################

resource "ibm_is_vpc" "vpc" {
  count                     = var.cluster_name_id == null && !var.classic_cluster ? 1 : 0
  name                      = "${var.prefix}-vpc"
  resource_group            = module.resource_group.resource_group_id
  address_prefix_management = "auto"
  tags                      = var.resource_tags
}

resource "ibm_is_public_gateway" "gateway" {
  count          = var.cluster_name_id == null && !var.classic_cluster ? 1 : 0
  name           = "${var.prefix}-gateway-1"
  vpc            = ibm_is_vpc.vpc[0].id
  resource_group = module.resource_group.resource_group_id
  zone           = "${var.region}-1"
}

resource "ibm_is_subnet" "subnet_zone_1" {
  count                    = var.cluster_name_id == null && !var.classic_cluster ? 1 : 0
  name                     = "${var.prefix}-subnet-1"
  vpc                      = ibm_is_vpc.vpc[0].id
  resource_group           = module.resource_group.resource_group_id
  zone                     = "${var.region}-1"
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.gateway[0].id
}

########################################################################################################################
# Classic Infrastructure: VLANs
########################################################################################################################

resource "ibm_network_vlan" "public_vlan" {
  count      = var.cluster_name_id == null && var.classic_cluster ? 1 : 0
  datacenter = var.datacenter
  type       = "PUBLIC"
}

resource "ibm_network_vlan" "private_vlan" {
  count           = var.cluster_name_id == null && var.classic_cluster ? 1 : 0
  datacenter      = var.datacenter
  type            = "PRIVATE"
  router_hostname = replace(ibm_network_vlan.public_vlan[0].router_hostname, "fcr", "bcr")
}

##############################################################################
# Create a Kubernetes cluster
##############################################################################

# Lookup the current default kube version for classic cluster
data "ibm_container_cluster_versions" "cluster_versions" {}

resource "ibm_container_vpc_cluster" "vpc_cluster" {
  count                = var.cluster_name_id == null && !var.classic_cluster ? 1 : 0
  name                 = "${var.prefix}-cluster"
  vpc_id               = ibm_is_vpc.vpc[0].id
  flavor               = "bx2.4x16"
  force_delete_storage = true
  resource_group_id    = module.resource_group.resource_group_id
  worker_count         = 2
  zones {
    subnet_id = ibm_is_subnet.subnet_zone_1[0].id
    name      = "${var.region}-1"
  }
  disable_outbound_traffic_protection = true
  tags                                = var.resource_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "ibm_container_cluster" "classic_cluster" {
  #checkov:skip=CKV2_IBM_7:Public endpoint is required for testing purposes
  count                = var.cluster_name_id == null && var.classic_cluster ? 1 : 0
  name                 = "${var.prefix}-cluster"
  datacenter           = var.datacenter
  default_pool_size    = 3
  hardware             = "shared"
  kube_version         = local.default_version
  force_delete_storage = true
  machine_type         = "b3c.4x16"
  public_vlan_id       = ibm_network_vlan.public_vlan[0].id
  private_vlan_id      = ibm_network_vlan.private_vlan[0].id
  wait_till            = "Normal"
  resource_group_id    = module.resource_group.resource_group_id
  tags                 = var.resource_tags

  timeouts {
    delete = "2h"
    create = "3h"
  }
}

data "ibm_container_vpc_cluster" "vpc_cluster_data" {
  count             = var.cluster_name_id != null && !var.classic_cluster ? 1 : 0
  name              = var.cluster_name_id
  resource_group_id = module.resource_group.resource_group_id
}

data "ibm_container_cluster" "classic_cluster_data" {
  count             = var.cluster_name_id != null && var.classic_cluster ? 1 : 0
  name              = var.cluster_name_id
  resource_group_id = module.resource_group.resource_group_id
}

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = local.cluster_id
  resource_group_id = module.resource_group.resource_group_id
  admin             = true
}

# Sleep to allow RBAC sync on cluster
resource "time_sleep" "wait_operators" {
  depends_on      = [data.ibm_container_cluster_config.cluster_config]
  create_duration = "60s"
}


########################################################################################################################
# Backup & Recovery for IKS/ROKS with Data Source Connector
########################################################################################################################

module "backup_recover_protect_iks" {
  source                       = "../.."
  cluster_id                   = local.cluster_id
  cluster_resource_group_id    = module.resource_group.resource_group_id
  cluster_config_endpoint_type = "private"
  add_dsc_rules_to_cluster_sg  = false
  kube_type                    = "kubernetes"
  ibmcloud_api_key             = var.ibmcloud_api_key
  enable_auto_protect          = false
  # --- B&R Instance ---
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_endpoint_type         = "public"
  brs_instance_name         = "${var.prefix}-brs-instance"
  brs_connection_name       = "${var.prefix}-brs-connection-${var.classic_cluster ? "IksClassic" : "IksVpc"}"
  brs_create_new_connection = true
  region                    = var.region
  connection_env_type       = var.classic_cluster ? "kIksClassic" : "kIksVpc"
  dsc_storage_class         = var.dsc_storage_class == null ? (var.classic_cluster ? "ibmc-block-silver" : "ibmc-vpc-block-metro-5iops-tier") : var.dsc_storage_class
  # --- Backup Policy (policy must already exist in the BRS instance) ---
  auto_protect_policy_name = "${var.prefix}-retention"
  access_tags              = var.access_tags
  resource_tags            = var.resource_tags
  policies = [
    {
      name = "${var.prefix}-retention"
      schedule = {
        unit = "Days"
        day_schedule = {
          frequency = 1
        }
      }
      retention = {
        unit     = "Days"
        duration = 30
      }
    }
  ]
  protection_groups = [
    {
      # ========================================
      # Basic Configuration
      # ========================================
      name        = "${var.prefix}-protection-group"
      policy_name = "${var.prefix}-retention"
      description = "Comprehensive protection group demonstrating advanced features"

      # ========================================
      # Priority & QoS
      # ========================================
      priority   = "kHigh"      # kLow, kMedium, kHigh
      qos_policy = "kBackupSSD" # kBackupHDD, kBackupSSD, kBackupAll

      # ========================================
      # Scheduling & Timing
      # ========================================
      start_time = {
        hour      = 2                  # 2 AM
        minute    = 30                 # 2:30 AM
        time_zone = "America/New_York" # EST timezone
      }

      # ========================================
      # Pause & Blackout Control
      # ========================================
      is_paused = false # Set to true to pause future runs
      # abort_in_blackouts = false  # Let running backups complete
      # pause_in_blackouts = true  # Don't start new backups during blackouts

      # ========================================
      # Kubernetes-Specific Features
      # ========================================
      enable_indexing       = true  # Enable search/indexing of backed up data
      leverage_csi_snapshot = true  # Use CSI snapshots for faster backups
      non_snapshot_backup   = false # Use snapshot-based backups
      volume_backup_failure = false # Don't fail entire backup if volume fails

      # ========================================
      # Objects to Protect
      # ========================================
      objects = [
        {
          name = kubernetes_namespace_v1.workload_ns.metadata[0].name

          # Backup configuration
          backup_only_pvc             = false # Backup entire namespace, not just PVCs
          fail_backup_on_hook_failure = false # Continue backup even if hooks fail

          # Resource filtering
          included_resources = [
            "deployments",
            "statefulsets",
            "secrets"
          ]

          include_pvcs = [
            {
              name = kubernetes_persistent_volume_claim_v1.test_app_pvc.metadata[0].name
            }
          ]

          # DO NOT include excluded_resources when using included_resources

          # Explicitly set include_params to null to prevent API from returning empty block
          include_params = null
        }
      ]

      # ========================================
      # Label-Based Filtering (Global)
      # ========================================
      include_params = {
        label_combination_method = "OR" # Include if ANY label matches
        label_vector = [
          {
            key   = "backup-enabled"
            value = "true"
          },
          {
            key   = "environment"
            value = "production"
          }
        ]
      }

      exclude_params = {
        label_combination_method = "AND" # Exclude only if ALL labels match
        label_vector = [
          {
            key   = "backup-exclude"
            value = "true"
          }
        ]
      }

      # ========================================
      # Alerts Configuration
      # ========================================
      alert_policy = {
        backup_run_status = [
          "kFailure",
          "kSlaViolation",
          "kWarning"
        ]

        alert_targets = [
          {
            email_address  = "backup-admin@example.com"
            language       = "en-us"
            recipient_type = "kTo"
          },
          {
            email_address  = "devops-team@example.com"
            language       = "en-us"
            recipient_type = "kCc"
          }
        ]

        raise_object_level_failure_alert                    = true
        raise_object_level_failure_alert_after_last_attempt = true
        raise_object_level_failure_alert_after_each_attempt = false
      }

      # ========================================
      # SLA Configuration
      # ========================================
      sla = [
        {
          backup_run_type = "kIncremental"
          sla_minutes     = 60 # 1 hour for incremental backups
        },
        {
          backup_run_type = "kFull"
          sla_minutes     = 120 # 2 hours for full backups
        }
      ]
    }
  ]

  # Use module-level recoveries only when the caller explicitly passes them.
  recoveries = length(var.recoveries) > 0 ? var.recoveries : []
}

# ========================================
# Dynamic Recovery Discovery and Execution
# ========================================

locals {
  created_protection_group_id = try(module.backup_recover_protect_iks.protection_group_ids["${var.prefix}-protection-group"], null)
  should_run_builtin_recovery = length(var.recoveries) == 0 && contains(["auto", "selective", "full", "cross"], var.recovery_mode)
}

resource "time_sleep" "wait_for_protection_group_visibility" {
  count = local.should_run_builtin_recovery ? 1 : 0

  depends_on      = [module.backup_recover_protect_iks]
  create_duration = "20s"
}

resource "ibm_backup_recovery_protection_group_run_request" "recovery_mode_backup_run" {
  count = local.should_run_builtin_recovery && var.recovery_mode == "auto" && var.auto_run_backup_before_recovery ? 1 : 0

  x_ibm_tenant_id      = module.backup_recover_protect_iks.brs_tenant_id
  instance_id          = module.backup_recover_protect_iks.brs_instance_guid
  region               = module.backup_recover_protect_iks.brs_instance_region
  endpoint_type        = module.backup_recover_protect_iks.brs_endpoint_type
  group_id = local.resolved_recovery_protection_group_id_api
  run_type = var.auto_recovery_run_type

  depends_on = [time_sleep.wait_for_protection_group_visibility]
}

resource "time_sleep" "wait_for_recovery_mode_snapshot_window" {
  count = local.should_run_builtin_recovery && var.recovery_mode == "auto" && var.auto_run_backup_before_recovery ? 1 : 0

  depends_on      = [ibm_backup_recovery_protection_group_run_request.recovery_mode_backup_run]
  create_duration = format("%ss", var.auto_recovery_wait_seconds)
}

data "ibm_backup_recovery_protection_groups" "all" {
  x_ibm_tenant_id = module.backup_recover_protect_iks.brs_tenant_id
  instance_id     = module.backup_recover_protect_iks.brs_instance_guid
  region          = module.backup_recover_protect_iks.brs_instance_region
  endpoint_type   = module.backup_recover_protect_iks.brs_endpoint_type

  depends_on = [module.backup_recover_protect_iks]
}

locals {
  discovered_recovery_protection_group = [for pg in data.ibm_backup_recovery_protection_groups.all.protection_groups : pg if pg.name == "${var.prefix}-protection-group"]
  resolved_recovery_protection_group_id = var.recovery_protection_group_id != null ? var.recovery_protection_group_id : (
    local.created_protection_group_id != null ? local.created_protection_group_id : (
      length(local.discovered_recovery_protection_group) > 0 ? local.discovered_recovery_protection_group[0].id : null
    )
  )
  resolved_recovery_protection_group_id_api = local.resolved_recovery_protection_group_id != null ? try(split("::", local.resolved_recovery_protection_group_id)[1], local.resolved_recovery_protection_group_id) : null
}

data "ibm_backup_recovery_protection_group_runs" "latest" {
  count = local.should_run_builtin_recovery ? 1 : 0

  x_ibm_tenant_id              = module.backup_recover_protect_iks.brs_tenant_id
  instance_id                  = module.backup_recover_protect_iks.brs_instance_guid
  region                       = module.backup_recover_protect_iks.brs_instance_region
  endpoint_type                = module.backup_recover_protect_iks.brs_endpoint_type
  protection_group_id          = local.resolved_recovery_protection_group_id_api
  include_object_details       = true
  num_runs                     = 5
  exclude_non_restorable_runs  = true

  depends_on = [
    module.backup_recover_protect_iks,
    time_sleep.wait_for_recovery_mode_snapshot_window
  ]
}

locals {
  manual_snapshot_ids = length(var.recovery_snapshot_ids) > 0 ? var.recovery_snapshot_ids : (
    try(trimspace(var.recovery_snapshot_id), "") != "" ? [var.recovery_snapshot_id] : []
  )
  discovered_snapshot_ids = distinct(compact(flatten([
    for run in(length(data.ibm_backup_recovery_protection_group_runs.latest) > 0 ? data.ibm_backup_recovery_protection_group_runs.latest[0].runs : []) : concat(
      flatten([
        for obj in try(run.objects, []) : flatten([
          for lsi in try(obj.local_snapshot_info, []) : [
            for si in try(lsi.snapshot_info, []) : try(si.snapshot_id, null)
          ]
        ])
      ]),
      flatten([
        for obj in try(run.objects, []) : flatten([
          for ai in try(obj.archival_info, []) : [
            for atr in try(ai.archival_target_results, []) : try(atr.snapshot_id, null)
          ]
        ])
      ]),
      flatten([
        for lbi in try(run.local_backup_info, []) : [try(lbi.snapshot_id, null)]
      ]),
      flatten([
        for ai in try(run.archival_info, []) : [
          for atr in try(ai.archival_target_results, []) : try(atr.snapshot_id, null)
        ]
      ])
    )
  ])))
  discovered_latest_snapshot_id = length(local.discovered_snapshot_ids) > 0 ? local.discovered_snapshot_ids[0] : null
  effective_snapshot_ids = length(local.manual_snapshot_ids) > 0 ? local.manual_snapshot_ids : (
    local.discovered_latest_snapshot_id != null ? [local.discovered_latest_snapshot_id] : []
  )
  effective_recovery_name = try(trimspace(var.recovery_name), "") != "" ? var.recovery_name : format(
    "Recover_Kubernetes_Namespaces_%s_%d_%s_%s",
    formatdate("MMM_D_YYYY", timeadd(plantimestamp(), "5h30m")),
    tonumber(formatdate("HH", timeadd(plantimestamp(), "5h30m"))),
    formatdate("mm", timeadd(plantimestamp(), "5h30m")),
    formatdate("AA", timeadd(plantimestamp(), "5h30m"))
  )
  recovery_target_source_id = try(
    tonumber(split("::", var.recovery_target_source_registration_id)[1]),
    tonumber(split("/", var.recovery_target_source_registration_id)[2]),
    null
  )
}

resource "ibm_backup_recovery" "discovered_recover_snapshot" {
  count = local.should_run_builtin_recovery ? 1 : 0

  x_ibm_tenant_id      = module.backup_recover_protect_iks.brs_tenant_id
  name                 = local.effective_recovery_name
  snapshot_environment = "kKubernetes"
  endpoint_type        = module.backup_recover_protect_iks.brs_endpoint_type
  instance_id          = module.backup_recover_protect_iks.brs_instance_guid
  region               = module.backup_recover_protect_iks.brs_instance_region

  kubernetes_params {
    recovery_action = var.recovery_action

    recover_namespace_params {
      target_environment = "kKubernetes"

      kubernetes_target_params {
        dynamic "objects" {
          for_each = local.effective_snapshot_ids
          content {
            snapshot_id         = objects.value
            protection_group_id = local.resolved_recovery_protection_group_id_api
          }
        }

        recovery_target_config {
          recover_to_new_source = var.recovery_mode == "cross"

          dynamic "new_source_config" {
            for_each = var.recovery_mode == "cross" ? [1] : []
            content {
              source {
                id = local.recovery_target_source_id
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    module.backup_recover_protect_iks,
    data.ibm_backup_recovery_protection_group_runs.latest
  ]

  lifecycle {
    precondition {
      condition     = local.resolved_recovery_protection_group_id_api != null
      error_message = "No protection group ID resolved for built-in recovery mode."
    }

    precondition {
      condition     = length(local.effective_snapshot_ids) > 0
      error_message = "No snapshot IDs available for built-in recovery mode. Increase auto_recovery_wait_seconds or provide recovery_snapshot_id manually."
    }

    precondition {
      condition     = var.recovery_mode != "cross" || local.recovery_target_source_id != null
      error_message = "Could not parse recovery_target_source_registration_id. Expected format tenant::id or tenant/::id."
    }
  }
}
