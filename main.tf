##############################################################################
# Locals
##############################################################################

locals {
  # --- Environment type detection ---
  is_vpc     = length(regexall("Vpc$", var.connection_env_type)) > 0
  is_classic = length(regexall("Classic$", var.connection_env_type)) > 0

  # --- BRS region: cluster region for new instances, existing instance region otherwise ---
  brs_region = var.existing_brs_instance_crn != null ? module.crn_parser[0].region : var.region

  # --- Cluster attributes (resolved from VPC or Classic data sources) ---
  cluster_crn                  = local.is_vpc ? data.ibm_container_vpc_cluster.vpc_cluster[0].crn : data.ibm_container_cluster.classic_cluster[0].crn
  cluster_private_endpoint_url = local.is_vpc ? data.ibm_container_vpc_cluster.vpc_cluster[0].private_service_endpoint_url : data.ibm_container_cluster.classic_cluster[0].private_service_endpoint_url
  cluster_public_endpoint_url  = local.is_vpc ? data.ibm_container_vpc_cluster.vpc_cluster[0].public_service_endpoint_url : data.ibm_container_cluster.classic_cluster[0].public_service_endpoint_url
  cluster_private_available    = local.is_vpc ? data.ibm_container_vpc_cluster.vpc_cluster[0].private_service_endpoint : data.ibm_container_cluster.classic_cluster[0].private_service_endpoint

  # --- Helm chart URI parsing ---
  uri_no_digest      = split("@", var.dsc_chart_uri)[0]
  chart_with_version = element(split("/", local.uri_no_digest), -1)
  dsc_chart          = split(":", local.chart_with_version)[0]
  dsc_chart_version  = replace(local.chart_with_version, "${local.dsc_chart}:", "")
  dsc_chart_location = replace(local.uri_no_digest, "/${local.chart_with_version}", "")

  # --- BRS instance attributes ---
  brs_tenant_id                        = module.backup_recovery_instance.tenant_id
  connection_id                        = module.backup_recovery_instance.connection_id
  registration_token                   = module.backup_recovery_instance.registration_token
  backup_recovery_instance_public_url  = module.backup_recovery_instance.brs_instance.extensions["endpoints.public"]
  backup_recovery_instance_private_url = module.backup_recovery_instance.brs_instance.extensions["endpoints.private"]
  brs_instance_guid                    = module.backup_recovery_instance.brs_instance_guid
  brs_instance_region                  = element(split(":", module.backup_recovery_instance.brs_instance_crn), 5)
  backup_recovery_instance_url         = var.brs_endpoint_type == "public" ? local.backup_recovery_instance_public_url : local.backup_recovery_instance_private_url

  # --- Protection policy ---
  use_existing_policy = var.policy.schedule == null && var.policy.retention == null

  # Only resolve policy_id if auto-protect is enabled
  policy_id = var.enable_auto_protect ? (
    local.use_existing_policy ? (
      data.ibm_backup_recovery_protection_policies.existing_policies[0].policies[0].id
      ) : (
      replace(ibm_backup_recovery_protection_policy.protection_policy[0].id, "${local.brs_tenant_id}::", "")
    )
  ) : null
}

##############################################################################
# CRN Parser (for existing BRS instance)
##############################################################################

module "crn_parser" {
  count = var.existing_brs_instance_crn == null ? 0 : 1

  source  = "terraform-ibm-modules/common-utilities/ibm//modules/crn-parser"
  version = "1.4.2"
  crn     = var.existing_brs_instance_crn
}

##############################################################################
# Backup Recovery Service Instance
##############################################################################

module "backup_recovery_instance" {
  source                    = "terraform-ibm-modules/backup-recovery/ibm"
  version                   = "v1.7.2"
  region                    = local.brs_region
  resource_group_id         = var.cluster_resource_group_id
  ibmcloud_api_key          = var.ibmcloud_api_key
  instance_name             = var.brs_instance_name
  existing_brs_instance_crn = var.existing_brs_instance_crn
  connection_name           = var.brs_connection_name
  create_new_connection     = var.brs_create_new_connection
  resource_tags             = var.resource_tags
  access_tags               = var.access_tags
  connection_env_type       = var.connection_env_type
}

##############################################################################
# Cluster Data Sources
##############################################################################

data "ibm_container_vpc_cluster" "vpc_cluster" {
  count = local.is_vpc ? 1 : 0

  name              = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}

data "ibm_container_cluster" "classic_cluster" {
  count = local.is_classic ? 1 : 0

  name              = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}

data "ibm_is_security_group" "clustersg" {
  count = var.add_dsc_rules_to_cluster_sg && local.is_vpc ? 1 : 0

  name = "kube-${var.cluster_id}"
}

data "ibm_container_vpc_worker_pool" "pool" {
  count = local.is_vpc ? 1 : 0

  cluster          = data.ibm_container_vpc_cluster.vpc_cluster[0].id
  worker_pool_name = data.ibm_container_vpc_cluster.vpc_cluster[0].worker_pools[0].name
}

##############################################################################
# Security Group Rules for Data Source Connector
##############################################################################

module "dsc_sg_rule" {
  count = var.add_dsc_rules_to_cluster_sg && local.is_vpc ? 1 : 0

  source                       = "terraform-ibm-modules/security-group/ibm"
  version                      = "v2.8.9"
  resource_group               = var.cluster_resource_group_id
  existing_security_group_name = "kube-${var.cluster_id}"
  use_existing_security_group  = true
  security_group_rules = [
    {
      name      = "allow-outbound-443-from-cdsc-to-brs-dataplane"
      direction = "outbound"
      remote    = "0.0.0.0/0"
      tcp = {
        port_max = 443
        port_min = 443
      }
    },
    {
      name      = "allow-outbound-29991-from-cdsc-to-brs-dataplane"
      direction = "outbound"
      remote    = "0.0.0.0/0"
      tcp = {
        port_max = 29991
        port_min = 29991
      }
    },
    {
      name      = "allow-outbound-50001-from-cdsc-to-brs-dataplane"
      direction = "outbound"
      remote    = "0.0.0.0/0"
      tcp = {
        port_max = 50001
        port_min = 50001
      }
    },
    {
      name      = "allow-inbound-3000-from-kube-cluster"
      direction = "inbound"
      remote    = data.ibm_is_security_group.clustersg[0].id
      tcp = {
        port_max = 3000
        port_min = 3000
      }
    }
  ]
}

##############################################################################
# Data Source Connector Worker Pool
##############################################################################

resource "ibm_container_vpc_worker_pool" "data_source_connector" {
  count = local.is_vpc ? 1 : 0

  cluster           = data.ibm_container_vpc_cluster.vpc_cluster[0].id
  worker_pool_name  = "data-source-connector-pool"
  flavor            = "bx2.4x16" # this flavor works for both IKS and OCP
  vpc_id            = data.ibm_container_vpc_worker_pool.pool[0].vpc_id
  worker_count      = ceil(var.dsc_replicas / length(data.ibm_container_vpc_worker_pool.pool[0].zones))
  resource_group_id = var.cluster_resource_group_id

  dynamic "zones" {
    for_each = data.ibm_container_vpc_worker_pool.pool[0].zones
    content {
      name      = zones.value.name
      subnet_id = zones.value.subnet_id
    }
  }

  labels = {
    "dedicated" = "data-source-connector"
  }
}

##############################################################################
# Data Source Connector Namespace
##############################################################################

resource "kubernetes_namespace_v1" "dsc_namespace" {
  metadata {
    name = var.dsc_namespace
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels
    ]
  }
}

##############################################################################
# Data Source Connector Helm Release
##############################################################################

resource "helm_release" "data_source_connector" {
  name             = var.dsc_name
  chart            = local.dsc_chart
  repository       = local.dsc_chart_location
  namespace        = kubernetes_namespace_v1.dsc_namespace.metadata[0].name
  version          = local.dsc_chart_version
  create_namespace = false
  timeout          = var.dsc_helm_timeout
  wait             = true
  atomic           = true
  upgrade_install  = true
  values = [
    yamlencode({
      secrets = {
        registrationToken = local.registration_token
      }
      image = {
        registry   = element(split("/", var.dsc_image_version), 0)
        namespace  = element(split("/", var.dsc_image_version), 1)
        repository = "${element(split("/", var.dsc_image_version), 2)}/${element(split("/", split(":", var.dsc_image_version)[0]), 3)}"
        tag        = split("@", split(":", var.dsc_image_version)[1])[0]
      }
      replicaCount     = var.dsc_replicas
      fullnameOverride = var.dsc_name
      nodeSelector = local.is_vpc ? {
        "dedicated" = "data-source-connector"
      } : {}
      volumeClaimTemplate = {
        storageClass = var.dsc_storage_class != null ? var.dsc_storage_class : (local.is_vpc ? "ibmc-vpc-block-metro-5iops-tier" : "ibmc-block-silver")
      }
    })
  ]

  depends_on = [
    module.dsc_sg_rule,
    ibm_container_vpc_worker_pool.data_source_connector,
    kubernetes_namespace_v1.dsc_namespace
  ]

  lifecycle {
    precondition {
      condition = (
        var.kube_type == "kubernetes" ? contains(["kIksVpc", "kIksClassic"], var.connection_env_type) :
        var.kube_type == "openshift" ? contains(["kRoksVpc", "kRoksClassic"], var.connection_env_type) :
        false
      )
      error_message = "Invalid connection_env_type '${var.connection_env_type}' for kube_type '${var.kube_type}'. When kube_type is 'kubernetes', connection_env_type must be 'kIksVpc' or 'kIksClassic'. When kube_type is 'openshift', connection_env_type must be 'kRoksVpc' or 'kRoksClassic'."
    }
  }
}

##############################################################################
# BRS Agent Service Account & RBAC
##############################################################################

# Ignore changes to image_pull_secret, secret, and annotations as they are
# updated by the cluster outside of terraform. This prevents terraform from
# recreating/updating the service account on every apply.
resource "kubernetes_service_account_v1" "brsagent" {
  metadata {
    name      = "brsagent"
    namespace = helm_release.data_source_connector.metadata.namespace
  }

  lifecycle {
    ignore_changes = [
      image_pull_secret,
      secret,
      metadata[0].annotations,
    ]
  }
}

resource "kubernetes_cluster_role_binding_v1" "brsagent_admin" {
  metadata {
    name = "brsagent-admin"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.brsagent.metadata[0].name
    namespace = kubernetes_service_account_v1.brsagent.metadata[0].namespace
  }
}

resource "kubernetes_secret_v1" "brsagent_token" {
  metadata {
    name      = "brsagent-token"
    namespace = kubernetes_service_account_v1.brsagent.metadata[0].namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.brsagent.metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

##############################################################################
# Protection Policy
##############################################################################

data "ibm_backup_recovery_protection_policies" "existing_policies" {
  count = local.use_existing_policy ? 1 : 0

  x_ibm_tenant_id = local.brs_tenant_id
  instance_id     = local.brs_instance_guid
  region          = local.brs_instance_region
  endpoint_type   = var.brs_endpoint_type
  policy_names    = [var.policy.name]
}

moved {
  from = ibm_backup_recovery_protection_policy.protection_policy
  to   = ibm_backup_recovery_protection_policy.protection_policy[0]
}

resource "ibm_backup_recovery_protection_policy" "protection_policy" {
  count = local.use_existing_policy ? 0 : 1

  x_ibm_tenant_id = local.brs_tenant_id
  name            = var.policy.name
  endpoint_type   = var.brs_endpoint_type
  instance_id     = local.brs_instance_guid
  region          = local.brs_instance_region

  backup_policy {
    regular {
      incremental {
        schedule {
          unit = var.policy.schedule.unit

          # --- Base frequency (required for Minutes/Hours/Days) ---
          dynamic "minute_schedule" {
            for_each = var.policy.schedule.unit == "Minutes" ? [var.policy.schedule] : []
            content {
              frequency = minute_schedule.value.frequency
            }
          }
          dynamic "hour_schedule" {
            for_each = var.policy.schedule.unit == "Hours" ? [var.policy.schedule] : []
            content {
              frequency = hour_schedule.value.frequency
            }
          }
          dynamic "day_schedule" {
            for_each = var.policy.schedule.unit == "Days" ? [var.policy.schedule] : []
            content {
              frequency = day_schedule.value.frequency
            }
          }

          # --- Optional extra layers (only when unit does not already cover them) ---
          dynamic "minute_schedule" {
            for_each = var.policy.schedule.minute_schedule != null && var.policy.schedule.unit != "Minutes" ? [var.policy.schedule.minute_schedule] : []
            content {
              frequency = minute_schedule.value.frequency
            }
          }
          dynamic "hour_schedule" {
            for_each = var.policy.schedule.hour_schedule != null && var.policy.schedule.unit != "Hours" ? [var.policy.schedule.hour_schedule] : []
            content {
              frequency = hour_schedule.value.frequency
            }
          }
          dynamic "day_schedule" {
            for_each = var.policy.schedule.day_schedule != null && var.policy.schedule.unit != "Days" ? [var.policy.schedule.day_schedule] : []
            content {
              frequency = day_schedule.value.frequency
            }
          }
          dynamic "week_schedule" {
            for_each = var.policy.schedule.week_schedule != null ? [var.policy.schedule.week_schedule] : []
            content {
              day_of_week = week_schedule.value.day_of_week
            }
          }
          dynamic "month_schedule" {
            for_each = var.policy.schedule.month_schedule != null ? [var.policy.schedule.month_schedule] : []
            content {
              day_of_week   = try(month_schedule.value.day_of_week, null)
              week_of_month = try(month_schedule.value.week_of_month, null)
              day_of_month  = try(month_schedule.value.day_of_month, null)
            }
          }
          dynamic "year_schedule" {
            for_each = var.policy.schedule.year_schedule != null ? [var.policy.schedule.year_schedule] : []
            content {
              day_of_year = year_schedule.value.day_of_year
            }
          }
        }
      }

      retention {
        duration = var.policy.retention.duration
        unit     = var.policy.retention.unit

        dynamic "data_lock_config" {
          for_each = var.policy.retention.data_lock_config != null ? [var.policy.retention.data_lock_config] : []
          content {
            mode                           = data_lock_config.value.mode
            unit                           = data_lock_config.value.unit
            duration                       = data_lock_config.value.duration
            enable_worm_on_external_target = data_lock_config.value.enable_worm_on_external_target
          }
        }
      }

      primary_backup_target {
        use_default_backup_target = var.policy.use_default_backup_target
      }

      dynamic "full_backups" {
        for_each = var.policy.full_schedule != null ? [var.policy.full_schedule] : []
        content {
          schedule {
            unit = full_backups.value.unit

            dynamic "day_schedule" {
              for_each = full_backups.value.day_schedule != null ? [full_backups.value.day_schedule] : []
              content {
                frequency = day_schedule.value.frequency
              }
            }
            dynamic "week_schedule" {
              for_each = full_backups.value.week_schedule != null ? [full_backups.value.week_schedule] : []
              content {
                day_of_week = week_schedule.value.day_of_week
              }
            }
            dynamic "month_schedule" {
              for_each = full_backups.value.month_schedule != null ? [full_backups.value.month_schedule] : []
              content {
                day_of_week   = try(month_schedule.value.day_of_week, null)
                week_of_month = try(month_schedule.value.week_of_month, null)
                day_of_month  = try(month_schedule.value.day_of_month, null)
              }
            }
            dynamic "year_schedule" {
              for_each = full_backups.value.year_schedule != null ? [full_backups.value.year_schedule] : []
              content {
                day_of_year = year_schedule.value.day_of_year
              }
            }
          }

          retention {
            duration = full_backups.value.retention.duration
            unit     = full_backups.value.retention.unit

            dynamic "data_lock_config" {
              for_each = full_backups.value.retention.data_lock_config != null ? [full_backups.value.retention.data_lock_config] : []
              content {
                mode                           = data_lock_config.value.mode
                unit                           = data_lock_config.value.unit
                duration                       = data_lock_config.value.duration
                enable_worm_on_external_target = data_lock_config.value.enable_worm_on_external_target
              }
            }
          }
        }
      }
    }

    dynamic "run_timeouts" {
      for_each = var.policy.run_timeouts != null ? var.policy.run_timeouts : []
      content {
        timeout_mins = run_timeouts.value.timeout_mins
        backup_type  = run_timeouts.value.backup_type
      }
    }
  }

  dynamic "blackout_window" {
    for_each = var.policy.blackout_window != null ? var.policy.blackout_window : []
    content {
      day = blackout_window.value.day
      start_time {
        hour      = blackout_window.value.start_time.hour
        minute    = blackout_window.value.start_time.minute
        time_zone = blackout_window.value.start_time.time_zone
      }
      end_time {
        hour      = blackout_window.value.end_time.hour
        minute    = blackout_window.value.end_time.minute
        time_zone = blackout_window.value.end_time.time_zone
      }
    }
  }

  dynamic "extended_retention" {
    for_each = var.policy.extended_retention != null ? var.policy.extended_retention : []
    content {
      schedule {
        unit      = extended_retention.value.schedule.unit
        frequency = extended_retention.value.schedule.frequency
      }
      retention {
        duration = extended_retention.value.retention.duration
        unit     = extended_retention.value.retention.unit

        dynamic "data_lock_config" {
          for_each = extended_retention.value.retention.data_lock_config != null ? [extended_retention.value.retention.data_lock_config] : []
          content {
            mode                           = data_lock_config.value.mode
            unit                           = data_lock_config.value.unit
            duration                       = data_lock_config.value.duration
            enable_worm_on_external_target = data_lock_config.value.enable_worm_on_external_target
          }
        }
      }
      run_type  = extended_retention.value.run_type
      config_id = extended_retention.value.config_id
    }
  }

  retry_options {
    retries             = 3
    retry_interval_mins = 5
  }
}

##############################################################################
# Source Registration
##############################################################################

resource "ibm_backup_recovery_source_registration" "source_registration" {
  x_ibm_tenant_id = local.brs_tenant_id
  environment     = "kKubernetes"
  connection_id   = local.connection_id
  endpoint_type   = var.brs_endpoint_type
  instance_id     = local.brs_instance_guid
  region          = local.brs_instance_region

  kubernetes_params {
    endpoint                = var.cluster_config_endpoint_type == "private" && local.cluster_private_available ? local.cluster_private_endpoint_url : local.cluster_public_endpoint_url
    kubernetes_distribution = var.kube_type == "openshift" ? "kROKS" : "kIKS"
    dynamic "auto_protect_config" {
      for_each = var.enable_auto_protect ? [1] : []
      content {
        is_default_auto_protected = true
        policy_id                 = local.policy_id
      }
    }
    data_mover_image_location                  = var.registration_images.data_mover
    velero_image_location                      = var.registration_images.velero
    velero_aws_plugin_image_location           = var.registration_images.velero_aws_plugin
    velero_openshift_plugin_image_location     = var.registration_images.velero_openshift_plugin
    init_container_image_location              = var.registration_images.init_container
    cohesity_dataprotect_plugin_image_location = var.registration_images.cohesity_dataprotect_plugin
    kubernetes_type                            = "kCluster"
    client_private_key                         = chomp(kubernetes_secret_v1.brsagent_token.data["token"])
  }

  depends_on = [helm_release.data_source_connector]
}

##############################################################################
# Tag cluster with BRS instance information
##############################################################################

resource "ibm_resource_tag" "cluster_brs_tag" {
  resource_id = local.cluster_crn
  tag_type    = "user"
  tags        = ["brs-region:${local.brs_instance_region}", "brs-guid:${local.brs_instance_guid}"]
}

##############################################################################
# Auto-protect cleanup (local-exec provisioner for destroy)
##############################################################################

# When auto-protect is enabled for the registration, it creates a protection
# group that is not currently deletable via terraform. This resource uses a
# local-exec provisioner to call a script that deletes the protection group.
resource "terraform_data" "delete_auto_protect_pg" {
  count = var.enable_auto_protect ? 1 : 0

  input = {
    url                 = local.backup_recovery_instance_url
    tenant              = local.brs_tenant_id
    endpoint_type       = var.brs_endpoint_type
    protection_group_id = ibm_backup_recovery_source_registration.source_registration.kubernetes_params[0].auto_protect_config[0].protection_group_id
    registration_id     = replace(ibm_backup_recovery_source_registration.source_registration.id, "${local.brs_tenant_id}::", "")
    api_key             = sensitive(var.ibmcloud_api_key)
  }

  triggers_replace = {
    api_key = sensitive(var.ibmcloud_api_key)
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}/scripts/delete_auto_protect_pg.sh https://${self.input.url} ${self.input.tenant} ${self.input.endpoint_type} ${self.input.protection_group_id} ${self.input.registration_id}"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      API_KEY = self.triggers_replace.api_key
    }
  }
}
