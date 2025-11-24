data "ibm_is_security_group" "clustersg" {
  count = var.add_dsc_rules_to_cluster_sg ? 1 : 0
  name  = "kube-${var.cluster_id}"
}

data "ibm_container_vpc_cluster" "cluster" {
  name              = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
}

module "dsc_sg_rule" {
  count                        = var.add_dsc_rules_to_cluster_sg ? 1 : 0
  source                       = "terraform-ibm-modules/security-group/ibm"
  version                      = "v2.8.0"
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

resource "helm_release" "data_source_connector" {
  depends_on       = [module.dsc_sg_rule]
  name             = var.dsc_name
  chart            = var.dsc_chart
  repository       = var.dsc_chart_location
  namespace        = var.dsc_namespace
  version          = var.dsc_chart_version
  create_namespace = true
  timeout          = 1500
  wait             = true
  values = [
    yamlencode({
      secrets = {
        registrationToken = var.dsc_registration_token
      }
      image = {
        namespace  = element(split("/", var.dsc_image), 1)
        repository = "${element(split("/", var.dsc_image), 2)}/${element(split("/", var.dsc_image), 3)}"
        tag        = var.dsc_image_version_tag
      }
      replicaCount     = var.dsc_replicas
      fullnameOverride = var.dsc_name
    })
  ]
}

resource "kubernetes_service_account" "brsagent" {
  depends_on = [helm_release.data_source_connector]
  metadata {
    name      = "brsagent"
    namespace = var.dsc_namespace
  }
}

# Create a cluster role binding for the service account
resource "kubernetes_cluster_role_binding" "brsagent_admin" {
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
    name      = kubernetes_service_account.brsagent.metadata[0].name
    namespace = var.dsc_namespace
  }
}

# Create a secret to store the service account token
resource "kubernetes_secret" "brsagent_token" {
  metadata {
    name      = "brsagent-token"
    namespace = var.dsc_namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.brsagent.metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

resource "ibm_backup_recovery_source_registration" "source_registration" {
  depends_on      = [kubernetes_secret.brsagent_token]
  x_ibm_tenant_id = var.brs_tenant_id
  environment     = "kKubernetes"
  connection_id   = var.connection_id
  name            = var.registration_name
  kubernetes_params {
    endpoint                               = var.cluster_config_endpoint_type == "private" || data.ibm_container_vpc_cluster.cluster.private_service_endpoint ? data.ibm_container_vpc_cluster.cluster.private_service_endpoint_url : data.ibm_container_vpc_cluster.cluster.public_service_endpoint_url
    kubernetes_distribution                = var.kube_type == "ROKS" ? "kROKS" : "kIKS"
    data_mover_image_location              = var.registration_images.data_mover
    velero_image_location                  = var.registration_images.velero
    velero_aws_plugin_image_location       = var.registration_images.velero_aws_plugin
    velero_openshift_plugin_image_location = var.registration_images.velero_openshift_plugin
    init_container_image_location          = var.registration_images.init_container
    kubernetes_type                        = "kCluster"
    client_private_key                     = chomp(kubernetes_secret.brsagent_token.data["token"])
  }
  endpoint_type = var.brs_endpoint_type
  instance_id   = var.brs_instance_guid
  region        = var.brs_instance_region
}

resource "ibm_backup_recovery_protection_policy" "protection_policy" {
  x_ibm_tenant_id = var.brs_tenant_id
  name            = var.policy.name
  endpoint_type   = var.brs_endpoint_type
  instance_id     = var.brs_instance_guid
  region          = var.brs_instance_region
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

          # --- Optional extra layers ---
          dynamic "minute_schedule" {
            for_each = var.policy.schedule.minute_schedule != null ? [var.policy.schedule.minute_schedule] : []
            content {
              frequency = minute_schedule.value.frequency
            }
          }
          dynamic "hour_schedule" {
            for_each = var.policy.schedule.hour_schedule != null ? [var.policy.schedule.hour_schedule] : []
            content {
              frequency = hour_schedule.value.frequency
            }
          }
          dynamic "day_schedule" {
            for_each = var.policy.schedule.day_schedule != null ? [var.policy.schedule.day_schedule] : []
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
              day_of_year = year_schedule.value.day_of_year # First or Last
            }
          }
        }
      }

      # ================================
      # RETENTION + DATA LOCK
      # ================================
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

      # ================================
      # PRIMARY TARGET
      # ================================
      primary_backup_target {
        use_default_backup_target = var.policy.use_default_backup_target
      }
    }
  }

  # ================================
  # RETRY OPTIONS
  # ================================
  retry_options {
    retries             = 1
    retry_interval_mins = 5
  }
}
