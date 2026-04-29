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
  cluster_endpoint             = var.cluster_config_endpoint_type == "private" && local.cluster_private_available ? local.cluster_private_endpoint_url : local.cluster_public_endpoint_url
  cluster_endpoint_port        = element(split(":", local.cluster_endpoint), -1)

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

  # Get resolved policy IDs from the BRS module
  resolved_policy_ids = module.backup_recovery_instance.resolved_policy_ids

  binaries_path = "/tmp"
}

resource "terraform_data" "install_dependencies" {
  count = var.install_required_binaries ? 1 : 0
  input = {
    binaries_path = local.binaries_path
  }
  provisioner "local-exec" {
    command     = "${path.module}/scripts/install-binaries.sh ${self.input.binaries_path}"
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}/scripts/install-binaries.sh ${self.input.binaries_path}"
    interpreter = ["/bin/bash", "-c"]
  }
}

##############################################################################
# CRN Parser (for existing BRS instance)
##############################################################################

module "crn_parser" {
  count = var.existing_brs_instance_crn == null ? 0 : 1

  source  = "terraform-ibm-modules/common-utilities/ibm//modules/crn-parser"
  version = "1.5.0"
  crn     = var.existing_brs_instance_crn
}

##############################################################################
# Backup Recovery Service Instance
##############################################################################

module "backup_recovery_instance" {
  source                    = "terraform-ibm-modules/backup-recovery/ibm"
  version                   = "v1.10.2"
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
  policies                  = var.policies
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

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  config_dir        = "${path.module}/kubeconfig"
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
  admin             = true

  # Wait for cluster to be ready before fetching config
  # This prevents timeouts when cluster is still provisioning
  depends_on = [
    data.ibm_container_vpc_cluster.vpc_cluster,
    data.ibm_container_cluster.classic_cluster
  ]
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
  version                      = "v2.9.0"
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
      name      = "allow-outbound-${local.cluster_endpoint_port}-from-cdsc-to-cluster-api"
      direction = "outbound"
      remote    = "0.0.0.0/0"
      tcp = {
        port_max = local.cluster_endpoint_port
        port_min = local.cluster_endpoint_port
      }
    }
  ]
}

##############################################################################
# Data Source Connector Worker Pool
##############################################################################

resource "ibm_container_vpc_worker_pool" "data_source_connector" {
  count = local.is_vpc && var.create_dsc_worker_pool ? 1 : 0

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

  taints {
    key    = "dedicated"
    value  = "data-source-connector"
    effect = "NoSchedule"
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
  atomic           = var.rollback_on_failure

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
      nodeSelector = local.is_vpc && var.create_dsc_worker_pool ? {
        "dedicated" = "data-source-connector"
      } : {}
      tolerations = local.is_vpc && var.create_dsc_worker_pool ? [
        {
          key      = "dedicated"
          operator = "Equal"
          value    = "data-source-connector"
          effect   = "NoSchedule"
        }
      ] : []
      volumeClaimTemplate = {
        storageClass = var.dsc_storage_class != null ? var.dsc_storage_class : (local.is_vpc ? "ibmc-vpc-block-metro-5iops-tier" : "ibmc-block-silver")
      }
    })
  ]

  depends_on = [
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
    endpoint                = local.cluster_endpoint
    kubernetes_distribution = var.kube_type == "openshift" ? "kROKS" : "kIKS"
    dynamic "auto_protect_config" {
      for_each = var.enable_auto_protect && var.auto_protect_policy_name != null ? [1] : []
      content {
        is_default_auto_protected = true
        policy_id                 = local.resolved_policy_ids[var.auto_protect_policy_name]
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

  depends_on = [
    helm_release.data_source_connector,
    terraform_data.wait_before_helm_destroy,
    module.backup_recovery_instance
  ]
}

# Wait for namespace cleanup during destroy before destroying helm release
# Uses a script to check for BRS-managed resources rather than a fixed time delay
resource "terraform_data" "wait_before_helm_destroy" {
  depends_on = [helm_release.data_source_connector]

  triggers_replace = {
    helm_release_id = helm_release.data_source_connector.id
    kubeconfig_path = data.ibm_container_cluster_config.cluster_config.config_file_path
    dsc_namespace   = var.dsc_namespace
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/wait_for_namespace_cleanup.sh '${self.triggers_replace.dsc_namespace}'"
    environment = {
      KUBECONFIG = self.triggers_replace.kubeconfig_path
    }
  }
}

# Wait for BRS asynchronous discovery to stabilize before reading protection sources.
resource "time_sleep" "wait_for_source_discovery" {
  depends_on = [
    ibm_backup_recovery_source_registration.source_registration,
    helm_release.data_source_connector,
    terraform_data.install_dependencies
  ]

  triggers = {
    connection_id = local.connection_id
    dsc_version   = var.dsc_image_version
  }

  create_duration = "5m"
}

data "ibm_backup_recovery_protection_sources" "sources" {
  x_ibm_tenant_id = local.brs_tenant_id
  environment     = "kKubernetes"
  instance_id     = local.brs_instance_guid
  region          = local.brs_instance_region
  endpoint_type   = var.brs_endpoint_type

  depends_on = [time_sleep.wait_for_source_discovery]
}

locals {
  # Flatten protection sources up to 3 levels deep to create a comprehensive map of object names (namespaces, PVCs, etc.) to IDs
  all_env_nodes = flatten([
    for env in(try(data.ibm_backup_recovery_protection_sources.sources.protection_sources, []) != null ? data.ibm_backup_recovery_protection_sources.sources.protection_sources : []) :
    (env.nodes != null ? env.nodes : [])
  ])

  all_l1_ps = flatten([
    for node in local.all_env_nodes : [
      for ps in(node.protection_source != null ? node.protection_source : []) : {
        id   = ps.id
        name = ps.name
      }
    ]
  ])

  all_l2_nodes = flatten([
    for node in local.all_env_nodes :
    (node.nodes != null ? node.nodes : [])
  ])

  all_l2_ps = flatten([
    for node in local.all_l2_nodes : [
      for ps in(node.protection_source != null ? node.protection_source : []) : {
        id   = ps.id
        name = ps.name
      }
    ]
  ])

  all_l3_nodes = flatten([
    for node in local.all_l2_nodes :
    (node.nodes != null ? node.nodes : [])
  ])

  all_l3_ps = flatten([
    for node in local.all_l3_nodes : [
      for ps in(node.protection_source != null ? node.protection_source : []) : {
        id   = ps.id
        name = ps.name
      }
    ]
  ])

  all_flat_objects  = concat(local.all_l1_ps, local.all_l2_ps, local.all_l3_ps)
  object_name_to_id = { for obj in local.all_flat_objects : obj.name => obj.id... }
}

##############################################################################
# Protection Groups (granular backup control)
##############################################################################

resource "ibm_backup_recovery_protection_group" "protection_group" {
  for_each = { for pg in var.protection_groups : pg.name => pg }

  x_ibm_tenant_id    = local.brs_tenant_id
  name               = each.value.name
  environment        = "kKubernetes"
  policy_id          = local.resolved_policy_ids[each.value.policy_name]
  description        = each.value.description
  is_paused          = each.value.is_paused
  abort_in_blackouts = each.value.abort_in_blackouts
  pause_in_blackouts = each.value.pause_in_blackouts
  priority           = each.value.priority
  qos_policy         = each.value.qos_policy
  endpoint_type      = var.brs_endpoint_type
  instance_id        = local.brs_instance_guid
  region             = local.brs_instance_region

  kubernetes_params {
    enable_indexing       = each.value.enable_indexing
    leverage_csi_snapshot = each.value.leverage_csi_snapshot
    non_snapshot_backup   = each.value.non_snapshot_backup
    volume_backup_failure = each.value.volume_backup_failure
    exclude_object_ids    = each.value.exclude_object_ids != null ? each.value.exclude_object_ids : []
    label_ids             = each.value.label_ids != null ? each.value.label_ids : []
    exclude_label_ids     = each.value.exclude_label_ids != null ? each.value.exclude_label_ids : []

    dynamic "objects" {
      for_each = each.value.objects != null ? each.value.objects : []
      content {
        id                          = objects.value.id != null ? objects.value.id : try(local.object_name_to_id[objects.value.name][0], null)
        backup_only_pvc             = objects.value.backup_only_pvc
        fail_backup_on_hook_failure = objects.value.fail_backup_on_hook_failure
        included_resources          = objects.value.included_resources
        excluded_resources          = objects.value.excluded_resources

        dynamic "include_pvcs" {
          for_each = objects.value.include_pvcs != null ? objects.value.include_pvcs : []
          content {
            id   = include_pvcs.value.id != null ? include_pvcs.value.id : try(local.object_name_to_id[include_pvcs.value.name][0], null)
            name = include_pvcs.value.name
          }
        }

        dynamic "exclude_pvcs" {
          for_each = objects.value.exclude_pvcs != null ? objects.value.exclude_pvcs : []
          content {
            id   = exclude_pvcs.value.id != null ? exclude_pvcs.value.id : try(local.object_name_to_id[exclude_pvcs.value.name][0], null)
            name = exclude_pvcs.value.name
          }
        }

        dynamic "include_params" {
          for_each = objects.value.include_params != null ? [objects.value.include_params] : []
          content {
            label_combination_method = include_params.value.label_combination_method

            dynamic "label_vector" {
              for_each = include_params.value.label_vector != null ? include_params.value.label_vector : []
              content {
                key   = label_vector.value.key
                value = label_vector.value.value
              }
            }

            dynamic "selected_resources" {
              for_each = include_params.value.selected_resources != null ? include_params.value.selected_resources : []
              content {
                api_group         = selected_resources.value.api_group
                is_cluster_scoped = selected_resources.value.is_cluster_scoped
                kind              = selected_resources.value.kind
                name              = selected_resources.value.name
                version           = selected_resources.value.version

                dynamic "resource_list" {
                  for_each = selected_resources.value.resource_list != null ? selected_resources.value.resource_list : []
                  content {
                    entity_id = resource_list.value.entity_id
                    name      = resource_list.value.name
                  }
                }
              }
            }
          }
        }

        dynamic "exclude_params" {
          for_each = objects.value.exclude_params != null ? [objects.value.exclude_params] : []
          content {
            label_combination_method = exclude_params.value.label_combination_method

            dynamic "label_vector" {
              for_each = exclude_params.value.label_vector != null ? exclude_params.value.label_vector : []
              content {
                key   = label_vector.value.key
                value = label_vector.value.value
              }
            }

            dynamic "selected_resources" {
              for_each = exclude_params.value.selected_resources != null ? exclude_params.value.selected_resources : []
              content {
                api_group         = selected_resources.value.api_group
                is_cluster_scoped = selected_resources.value.is_cluster_scoped
                kind              = selected_resources.value.kind
                name              = selected_resources.value.name
                version           = selected_resources.value.version

                dynamic "resource_list" {
                  for_each = selected_resources.value.resource_list != null ? selected_resources.value.resource_list : []
                  content {
                    entity_id = resource_list.value.entity_id
                    name      = resource_list.value.name
                  }
                }
              }
            }
          }
        }

        dynamic "quiesce_groups" {
          for_each = objects.value.quiesce_groups != null ? objects.value.quiesce_groups : []
          content {
            quiesce_mode = quiesce_groups.value.quiesce_mode

            dynamic "quiesce_rules" {
              for_each = quiesce_groups.value.quiesce_rules
              content {
                dynamic "pod_selector_labels" {
                  for_each = quiesce_rules.value.pod_selector_labels != null ? quiesce_rules.value.pod_selector_labels : []
                  content {
                    key   = pod_selector_labels.value.key
                    value = pod_selector_labels.value.value
                  }
                }

                dynamic "pre_snapshot_hooks" {
                  for_each = quiesce_rules.value.pre_snapshot_hooks
                  content {
                    commands      = pre_snapshot_hooks.value.commands
                    container     = pre_snapshot_hooks.value.container
                    fail_on_error = pre_snapshot_hooks.value.fail_on_error
                    timeout       = pre_snapshot_hooks.value.timeout
                  }
                }

                dynamic "post_snapshot_hooks" {
                  for_each = quiesce_rules.value.post_snapshot_hooks
                  content {
                    commands      = post_snapshot_hooks.value.commands
                    container     = post_snapshot_hooks.value.container
                    fail_on_error = post_snapshot_hooks.value.fail_on_error
                    timeout       = post_snapshot_hooks.value.timeout
                  }
                }
              }
            }
          }
        }
      }
    }

    # Global label-based inclusion filter
    dynamic "include_params" {
      for_each = each.value.include_params != null ? [each.value.include_params] : []
      content {
        label_combination_method = include_params.value.label_combination_method

        dynamic "label_vector" {
          for_each = include_params.value.label_vector != null ? include_params.value.label_vector : []
          content {
            key   = label_vector.value.key
            value = label_vector.value.value
          }
        }

        dynamic "selected_resources" {
          for_each = include_params.value.selected_resources != null ? include_params.value.selected_resources : []
          content {
            api_group         = selected_resources.value.api_group
            is_cluster_scoped = selected_resources.value.is_cluster_scoped
            kind              = selected_resources.value.kind
            name              = selected_resources.value.name
            version           = selected_resources.value.version

            dynamic "resource_list" {
              for_each = selected_resources.value.resource_list != null ? selected_resources.value.resource_list : []
              content {
                entity_id = resource_list.value.entity_id
                name      = resource_list.value.name
              }
            }
          }
        }
      }
    }

    # Global label-based exclusion filter
    dynamic "exclude_params" {
      for_each = each.value.exclude_params != null ? [each.value.exclude_params] : []
      content {
        label_combination_method = exclude_params.value.label_combination_method

        dynamic "label_vector" {
          for_each = exclude_params.value.label_vector != null ? exclude_params.value.label_vector : []
          content {
            key   = label_vector.value.key
            value = label_vector.value.value
          }
        }

        dynamic "selected_resources" {
          for_each = exclude_params.value.selected_resources != null ? exclude_params.value.selected_resources : []
          content {
            api_group         = selected_resources.value.api_group
            is_cluster_scoped = selected_resources.value.is_cluster_scoped
            kind              = selected_resources.value.kind
            name              = selected_resources.value.name
            version           = selected_resources.value.version

            dynamic "resource_list" {
              for_each = selected_resources.value.resource_list != null ? selected_resources.value.resource_list : []
              content {
                entity_id = resource_list.value.entity_id
                name      = resource_list.value.name
              }
            }
          }
        }
      }
    }
  }

  dynamic "alert_policy" {
    for_each = each.value.alert_policy != null ? [each.value.alert_policy] : []
    content {
      backup_run_status                                   = alert_policy.value.backup_run_status
      raise_object_level_failure_alert                    = alert_policy.value.raise_object_level_failure_alert
      raise_object_level_failure_alert_after_each_attempt = alert_policy.value.raise_object_level_failure_alert_after_each_attempt
      raise_object_level_failure_alert_after_last_attempt = alert_policy.value.raise_object_level_failure_alert_after_last_attempt

      dynamic "alert_targets" {
        for_each = alert_policy.value.alert_targets != null ? alert_policy.value.alert_targets : []
        content {
          email_address  = alert_targets.value.email_address
          language       = alert_targets.value.language
          recipient_type = alert_targets.value.recipient_type
        }
      }
    }
  }

  dynamic "sla" {
    for_each = each.value.sla != null ? each.value.sla : []
    content {
      backup_run_type = sla.value.backup_run_type
      sla_minutes     = sla.value.sla_minutes
    }
  }

  dynamic "start_time" {
    for_each = each.value.start_time != null ? [each.value.start_time] : []
    content {
      hour      = start_time.value.hour
      minute    = start_time.value.minute
      time_zone = start_time.value.time_zone
    }
  }

  dynamic "advanced_configs" {
    for_each = each.value.advanced_configs != null ? each.value.advanced_configs : []
    content {
      key   = advanced_configs.value.key
      value = advanced_configs.value.value
    }
  }

  depends_on = [
    data.ibm_backup_recovery_protection_sources.sources,
    time_sleep.wait_for_source_discovery
  ]

  lifecycle {
    precondition {
      condition     = length(local.all_flat_objects) > 0
      error_message = <<-EOT
        Protection sources are empty. The Data Source Connector may not have completed
        its initial discovery yet. Wait a few minutes and run 'terraform apply' again.
      EOT
    }

    # Ignore changes to include_params within objects when it's returned as empty by the API
    # This prevents perpetual drift when include_params is not explicitly set in the configuration
    ignore_changes = [
      kubernetes_params[0].objects[0].include_params
    ]
  }
}

##############################################################################
# Tag cluster with BRS instance information
##############################################################################

# Adds BRS tags to identify which instance is protecting this cluster.
# Set add_cluster_tags = false to prevent tag drift when cluster tags are managed externally.
resource "ibm_resource_tag" "cluster_brs_tag" {
  count = var.add_cluster_tags ? 1 : 0

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
  depends_on = [terraform_data.install_dependencies]
  count      = var.enable_auto_protect ? 1 : 0

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


##############################################################################
# Restore the backups to Same or different cluster
##############################################################################

resource "ibm_backup_recovery" "recover_snapshot" {
  for_each = { for recovery in var.recoveries : recovery.name => recovery }

  x_ibm_tenant_id      = local.brs_tenant_id
  name                 = each.value.name
  snapshot_environment = each.value.snapshot_environment
  endpoint_type        = var.brs_endpoint_type
  instance_id          = local.brs_instance_guid
  region               = local.brs_instance_region

  # Kubernetes-specific recovery parameters
  dynamic "kubernetes_params" {
    for_each = each.value.kubernetes_params != null ? [each.value.kubernetes_params] : []
    content {
      recovery_action = kubernetes_params.value.recovery_action

      # Objects to recover
      dynamic "objects" {
        for_each = kubernetes_params.value.objects
        content {
          snapshot_id           = objects.value.snapshot_id
          point_in_time_usecs   = objects.value.point_in_time_usecs
          protection_group_id   = objects.value.protection_group_id
          protection_group_name = objects.value.protection_group_name
          recover_from_standby  = objects.value.recover_from_standby
        }
      }
    }
  }

  depends_on = [
    ibm_backup_recovery_protection_group.protection_group,
    ibm_backup_recovery_source_registration.source_registration
  ]
}


##############################################################################
# Cleanup Runtime BRS-agent-created resources during destroy
##############################################################################
# BRS agent creates namespaces and CRBs dynamically at runtime that Terraform
# doesn't manage. This cleanup resource ensures they are deleted during destroy.
# Cluster credentials are stored in triggers at apply time so they are available
# at destroy time without dependency on kubeconfig files (required for Schematics).
resource "terraform_data" "cleanup_brs_agent_resources" {
  triggers_replace = {
    cluster_id      = var.cluster_id
    kubeconfig_path = var.external_kubeconfig_path != null ? var.external_kubeconfig_path : data.ibm_container_cluster_config.cluster_config.config_file_path
    binaries_path   = local.binaries_path
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/cleanup_brs_agent_resources.sh ${self.triggers_replace.binaries_path}"
    environment = {
      KUBECONFIG = self.triggers_replace.kubeconfig_path
    }
  }

  depends_on = [
    ibm_backup_recovery_source_registration.source_registration,
    helm_release.data_source_connector,
    kubernetes_cluster_role_binding_v1.brsagent_admin
  ]
}
