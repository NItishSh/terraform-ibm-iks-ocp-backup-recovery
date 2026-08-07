##############################################################################
# Locals
##############################################################################

locals {
  # --- Environment type detection ---
  is_vpc     = length(regexall("Vpc$", var.connection_env_type)) > 0
  is_classic = length(regexall("Classic$", var.connection_env_type)) > 0

  # --- Deployment mode flags ---
  # DSC, source registration, and protection groups are always deployed in every
  # deployment_mode. deploy_recovery is the only mode-gated flag.
  deploy_recovery = var.deployment_mode == "full_backup_recovery"

  # --- BRS region: cluster region for new instances, existing instance region otherwise ---
  brs_region = var.existing_brs_instance_crn != null && var.existing_brs_instance_crn != "" ? split(":", var.existing_brs_instance_crn)[5] : var.region

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
  backup_recovery_instance_public_url  = nonsensitive(module.backup_recovery_instance.brs_instance.extensions["endpoints.public"])
  backup_recovery_instance_private_url = nonsensitive(module.backup_recovery_instance.brs_instance.extensions["endpoints.private"])
  brs_instance_guid                    = module.backup_recovery_instance.brs_instance_guid
  brs_instance_region                  = element(split(":", module.backup_recovery_instance.brs_instance_crn), 5)

  # URL used by Terraform provider resources and scripts to reach the BRS API.
  # The DSC Helm chart does NOT use this URL — it reads the BRS private endpoint
  # directly from the cluster_endpoint field embedded in the registration token JWT.
  # The VPE Gateway makes that private hostname resolvable inside the VPC without
  # any change to this URL.
  backup_recovery_instance_url = var.brs_endpoint_type == "public" ? local.backup_recovery_instance_public_url : local.backup_recovery_instance_private_url

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
# IAM Auth Token (retrieved from provider credentials)
##############################################################################

##############################################################################
# CRN Parser (for existing BRS instance)
##############################################################################

module "crn_parser" {
  source  = "terraform-ibm-modules/common-utilities/ibm//modules/crn-parser"
  version = "1.5.0"
  crn     = var.existing_brs_instance_crn != null && var.existing_brs_instance_crn != "" ? var.existing_brs_instance_crn : ""
}

##############################################################################
# Backup Recovery Service Instance
##############################################################################

module "backup_recovery_instance" {
  source                    = "terraform-ibm-modules/backup-recovery/ibm"
  version                   = "1.12.3"
  region                    = local.brs_region
  resource_group_id         = var.brs_resource_group_id != null ? var.brs_resource_group_id : var.cluster_resource_group_id
  ibmcloud_api_key          = var.ibmcloud_api_key
  instance_name             = var.brs_instance_name
  existing_brs_instance_crn = var.existing_brs_instance_crn != null && var.existing_brs_instance_crn != "" ? var.existing_brs_instance_crn : null
  create_new_instance       = var.create_new_brs_instance
  connection_name           = var.brs_connection_name
  create_new_connection     = var.brs_create_new_connection
  resource_tags             = var.resource_tags
  access_tags               = var.access_tags
  endpoint_type             = var.brs_endpoint_type
  connection_env_type       = var.connection_env_type
  policies                  = var.policies
}

##############################################################################
# Cluster Data Sources
##############################################################################

data "ibm_container_vpc_cluster" "vpc_cluster" {
  count    = local.is_vpc ? 1 : 0
  provider = ibm.cluster

  name              = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}

data "ibm_container_cluster" "classic_cluster" {
  count    = local.is_classic ? 1 : 0
  provider = ibm.cluster

  name              = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
}

data "ibm_container_cluster_config" "cluster_config" {
  provider = ibm.cluster

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
  count    = local.is_vpc ? 1 : 0
  provider = ibm.cluster

  cluster          = data.ibm_container_vpc_cluster.vpc_cluster[0].id
  worker_pool_name = data.ibm_container_vpc_cluster.vpc_cluster[0].worker_pools[0].name
}

##############################################################################
# VPC + Subnet auto-discovery  (used when create_brs_vpe = true)
#
# ibm_container_vpc_cluster does not export vpc_id as a top-level attribute.
# We flatten all subnet IDs from worker_pools -> zones -> subnets, look each
# up via ibm_is_subnet (one per subnet, all IDs known at plan time from the
# worker_pool splat), then use the first result to derive the VPC ID.
# Users no longer need to supply vpc_id or vpc_subnets when create_brs_vpe = true.
##############################################################################

locals {
  # All subnet IDs attached to the cluster's worker pools — flattened then
  # deduplicated. A single-zone cluster exposes the same subnet ID once per
  # worker pool, so without distinct() the list has duplicates that produce
  # duplicate for_each keys in the VPE gateway reserved-IP module.
  # For classic clusters is_vpc is false so this will be [].
  cluster_subnet_ids = local.is_vpc ? distinct(flatten(
    data.ibm_container_vpc_cluster.vpc_cluster[0].worker_pools[*].zones[*].subnets[*].id
  )) : []

  # Only look up cluster subnets when ALL of the following hold:
  #   1. VPE creation is requested
  #   2. Caller did NOT supply vpc_subnets explicitly (auto-discovery path)
  #   3. The cluster is a VPC cluster
  # When the caller supplies vpc_subnets (including when a new cluster is being
  # created in the same apply), skip the lookup entirely — the list length is
  # already known at plan time from the caller-supplied value, so the count
  # below is always static and Terraform can plan correctly.
  cluster_subnet_lookup_count = (
    var.create_brs_vpe &&
    length(var.vpc_subnets) == 0 &&
    local.is_vpc &&
    length(local.cluster_subnet_ids) > 0
  ) ? length(local.cluster_subnet_ids) : 0
}

# Look up every unique cluster subnet individually.
# The IDs come from worker_pools splat and are known at plan time, so the
# count is static and Terraform can plan correctly without a two-phase apply.
data "ibm_is_subnet" "cluster_subnet" {
  count      = local.cluster_subnet_lookup_count
  provider   = ibm.cluster
  identifier = local.cluster_subnet_ids[count.index]
}

locals {
  # VPC ID: user-supplied takes precedence; auto-derived from the first
  # cluster subnet lookup otherwise.
  resolved_vpc_id = var.vpc_id != null ? var.vpc_id : (
    local.cluster_subnet_lookup_count > 0 ? data.ibm_is_subnet.cluster_subnet[0].vpc : null
  )

  # Subnet list: user-supplied takes precedence; built from the per-subnet
  # lookups otherwise. Deduplication of cluster_subnet_ids ensures each subnet
  # object appears exactly once — required by the VPE module's for_each key.
  resolved_vpc_subnets = length(var.vpc_subnets) > 0 ? var.vpc_subnets : (
    local.cluster_subnet_lookup_count > 0 ? [for s in data.ibm_is_subnet.cluster_subnet : {
      name = s.name
      id   = s.id
      zone = s.zone
    }] : []
  )
}

##############################################################################
# Security Group Rules for Data Source Connector
##############################################################################

module "dsc_sg_rule" {
  count = var.add_dsc_rules_to_cluster_sg && local.is_vpc ? 1 : 0

  source  = "terraform-ibm-modules/security-group/ibm"
  version = "v2.9.1"
  providers = {
    ibm = ibm.cluster
  }
  resource_group               = var.cluster_resource_group_id
  existing_security_group_name = "kube-${var.cluster_id}"
  use_existing_security_group  = true
  security_group_rules = [
    {
      name      = "allow-outbound-443-from-cdsc-to-brs-dataplane"
      direction = "outbound"
      remote    = "0.0.0.0/0"
      protocol  = "tcp"
      port_min  = 443
      port_max  = 443
    },
    {
      name      = "allow-outbound-29991-from-cdsc-to-brs-dataplane"
      direction = "outbound"
      remote    = "0.0.0.0/0"
      protocol  = "tcp"
      port_min  = 29991
      port_max  = 29991
    },
    {
      name      = "allow-outbound-${local.cluster_endpoint_port}-from-cdsc-to-cluster-api"
      direction = "outbound"
      remote    = "0.0.0.0/0"
      protocol  = "tcp"
      port_min  = local.cluster_endpoint_port
      port_max  = local.cluster_endpoint_port
    }
  ]
}

##############################################################################
# S2S IAM Authorization Policy (cross-account: source VPC → BRS instance)
##############################################################################

# When the BRS instance is in a different IBM Cloud account than the cluster VPC,
# the VPEG target (the BRS CRN) lives in the target account.  The VPC
# Infrastructure Service in the source account needs a Viewer authorization on
# the BRS instance before the VPEG can be created.
#
# Policy model (created in the TARGET / BRS account):
#   Subject  : VPC Infrastructure Services / endpoint-gateway  in source account
#   Resource : backup-recovery instance GUID
#   Role     : Viewer
#
# For same-account deployments (brs_source_account_id == null) this module
# creates no resources (service_map is empty).
module "brs_s2s_auth" {
  count   = var.create_brs_vpe && var.brs_source_account_id != null ? 1 : 0
  source  = "terraform-ibm-modules/s2s-auth/ibm"
  version = "2.3.1"

  enable_cbr = false

  service_map = {
    "brs-vpe-source-to-brs-target" = {
      # Source: VPC Infrastructure Services / endpoint-gateway in the SOURCE account
      source_service_name       = "is"
      source_resource_type      = "endpoint-gateway"
      source_service_account_id = var.brs_source_account_id

      # Target: the specific BRS instance in this (TARGET) account
      target_service_name         = "backup-recovery"
      target_resource_instance_id = local.brs_instance_guid

      roles       = ["Viewer"]
      description = "Allow VPC endpoint-gateway in account ${var.brs_source_account_id} to target BRS instance ${local.brs_instance_guid}"
    }
  }

  depends_on = [module.backup_recovery_instance]
}

##############################################################################
# Virtual Private Endpoint Gateway for BRS
##############################################################################

# VPE Gateway naming: use a short, fixed vpc_name to avoid exceeding IBM's
# 63-character resource name limit. The vpc_name is only used in the VPE name
# template (e.g., "<prefix>-<vpc_name>-vpe-gateway"); the actual vpc_id is
# specified separately and is what matters for API operations.
# Using the VPC UUID (36+ chars) would cause the final VPE name to exceed 63 chars.
locals {
  # vpc_name is used only in the VPE name template; the actual vpc_id is passed separately.
  # Using a fixed string keeps the final VPE gateway name within the 63-character limit.
  brs_vpe_vpc_name = local.is_vpc ? "vpc" : "vpc"
}

module "brs_vpe" {
  count   = var.create_brs_vpe && local.is_vpc ? 1 : 0
  source  = "terraform-ibm-modules/vpe-gateway/ibm"
  version = "5.3.5"
  providers = {
    ibm = ibm.cluster
  }

  # Use var.region (the cluster's region, always known at plan time) rather than
  # local.brs_instance_region (derived from the BRS CRN, unknown until apply).
  # The VPE is always co-located with the cluster; the BRS instance region only
  # diverges when using cross-region replication (not supported here).
  region            = var.region
  prefix            = var.brs_vpe_name != null ? var.brs_vpe_name : "brs"
  vpc_name          = local.brs_vpe_vpc_name
  vpc_id            = local.resolved_vpc_id
  subnet_zone_list  = local.resolved_vpc_subnets
  resource_group_id = var.cluster_resource_group_id

  # Attach to the Kubernetes VPEG security group (kube-vpegw-<vpc-id>).
  # IKS/ROKS automatically creates this SG on every VPC cluster and it is
  # pre-configured to allow the cluster worker nodes to reach VPE targets.
  security_group_ids = [data.ibm_is_security_group.kube_vpeg_sg[0].id]

  # vpe_name is set explicitly so the for_each key in the child module is a
  # static string known at plan time (not derived from vpc_id or CRN).
  # Without this, the key would be "${prefix}-${vpc_name}-backup-recovery"
  # where vpc_name comes from the worker-pool data source — unknown at plan.
  cloud_service_by_crn = [
    {
      crn          = module.backup_recovery_instance.brs_instance_crn
      service_name = "backup-recovery"
      vpe_name     = var.brs_vpe_name != null ? var.brs_vpe_name : "${var.brs_connection_name}-vpe"
    }
  ]

  depends_on = [module.brs_s2s_auth]
}

# Fetch the kube-vpegw-<vpc-id> security group that IKS/ROKS creates on every
# VPC cluster. It is pre-scoped to allow cluster nodes to reach VPE endpoints.
data "ibm_is_security_group" "kube_vpeg_sg" {
  count    = var.create_brs_vpe && local.is_vpc ? 1 : 0
  provider = ibm.cluster
  name     = "kube-vpegw-${local.resolved_vpc_id}"
}

##############################################################################
# Data Source Connector Worker Pools (Single-Zone)
##############################################################################

locals {
  # Calculate workers per zone based on total replicas
  # Use the dsc_worker_pool_zones variable (defaults to 1) for count calculation
  # This ensures the count is known at plan time
  num_zones = local.is_vpc && var.create_dsc_worker_pool ? var.dsc_worker_pool_zones : 0
  # Convert zones set to list for indexing (only used after apply)
  zones_list    = local.is_vpc && var.create_dsc_worker_pool ? [for zone in data.ibm_container_vpc_worker_pool.pool[0].zones : zone] : []
  base_workers  = local.num_zones > 0 ? floor(var.dsc_replicas / local.num_zones) : 0
  extra_workers = local.num_zones > 0 ? var.dsc_replicas % local.num_zones : 0

  # Resolved storage class for the DSC PVC — used in both the Helm values and
  # the diagnostics script so the expression is not repeated.
  dsc_storage_class = var.dsc_storage_class != null ? var.dsc_storage_class : (local.is_vpc ? "ibmc-vpc-block-metro-5iops-tier" : "ibmc-block-silver")
}

resource "ibm_container_vpc_worker_pool" "data_source_connector" {
  count    = local.is_vpc && var.create_dsc_worker_pool ? local.num_zones : 0
  provider = ibm.cluster

  cluster           = data.ibm_container_vpc_cluster.vpc_cluster[0].id
  worker_pool_name  = "dsc-pool-zone-${count.index + 1}"
  flavor            = var.dsc_worker_pool_flavor
  vpc_id            = data.ibm_container_vpc_worker_pool.pool[0].vpc_id
  worker_count      = count.index < local.extra_workers ? local.base_workers + 1 : local.base_workers
  resource_group_id = var.cluster_resource_group_id

  zones {
    name      = local.zones_list[count.index].name
    subnet_id = local.zones_list[count.index].subnet_id
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
# Wait for DSC Worker Pool Node(s) to be Ready
##############################################################################

# The IBM Cloud provider marks the worker pool as "created" as soon as the API
# confirms the pool exists, but the underlying VMs may not be in Kubernetes
# Ready state for several minutes after that. Scheduling the Helm release
# immediately causes the DSC pod to stay Pending until the node becomes Ready,
# which exhausts the Helm timeout (context deadline exceeded).
# This resource runs kubectl wait after pool creation to block the Helm install
# until at least one node with the "dedicated=data-source-connector" label is
# schedulable.  It is a no-op when create_dsc_worker_pool is false.
resource "terraform_data" "wait_for_dsc_node_ready" {
  count = local.is_vpc && var.create_dsc_worker_pool ? 1 : 0

  depends_on = [ibm_container_vpc_worker_pool.data_source_connector]

  input = {
    kubeconfig_path = data.ibm_container_cluster_config.cluster_config.config_file_path
  }

  provisioner "local-exec" {
    # Wait up to 15 minutes for at least one DSC node to become Ready.
    # --selector matches the label applied to every dsc-pool-zone-* worker pool.
    # `kubectl wait node --selector=...` fails immediately with "no matching resources
    # found" when zero nodes with that label exist yet (the VM is still provisioning).
    # So we first poll until at least one matching node appears, then wait for Ready.
    #
    # After the node reports Ready we sleep an additional 120 s. A node enters the
    # Ready condition as soon as its kubelet registers, but the scheduler's internal
    # cache and taint/toleration logic may not yet have accepted the node. Without
    # this extra delay the Helm install starts while the scheduler still considers
    # the node unschedulable, the DSC pod stays Pending for the entire Helm timeout,
    # and the install fails with "context deadline exceeded".
    command     = <<-EOT
      echo "Waiting for DSC node to appear (label dedicated=data-source-connector)..."
      for i in $(seq 1 90); do
        if kubectl get nodes --selector='dedicated=data-source-connector' --no-headers 2>/dev/null | grep -q .; then
          echo "Node found, waiting for Ready condition..."
          kubectl wait node --selector='dedicated=data-source-connector' --for=condition=Ready --timeout=900s || exit 1
          echo "Node is Ready. Sleeping 120 s to allow scheduler cache to sync..."
          sleep 120
          echo "Scheduler sync wait complete."
          exit 0
        fi
        echo "No DSC node yet, retry $i/90 (sleeping 10s)..."
        sleep 10
      done
      echo "Timed out waiting for DSC node to appear after 15 minutes"
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.input.kubeconfig_path
    }
  }
}

##############################################################################
# Data Source Connector Namespace
##############################################################################

resource "kubernetes_namespace_v1" "dsc_namespace" {
  metadata {
    name = var.dsc_namespace
  }

  timeouts {
    delete = "10m"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels
    ]
  }
}

##############################################################################
# Freeze immutable Helm values at first install
##############################################################################

# volumeClaimTemplate.storageClass is an immutable StatefulSet field —
# the Kubernetes API rejects any helm upgrade that changes it.
# Storing it in input under ignore_changes freezes the value at first apply
# so post-install changes to var.dsc_storage_class never reach helm upgrade.
# To change it: terraform destroy, clean up PVCs/PVs, then terraform apply.
resource "terraform_data" "dsc_immutable_values" {
  input = {
    storage_class   = local.dsc_storage_class
    namespace       = kubernetes_namespace_v1.dsc_namespace.metadata[0].name
    kubeconfig_path = data.ibm_container_cluster_config.cluster_config.config_file_path
    dsc_name        = var.dsc_name
  }

  lifecycle {
    ignore_changes = [input]
  }

  # On destroy: delete DSC PVCs after helm uninstall (helm_release depends_on
  # this resource, so it is destroyed first). RECLAIMPOLICY=Retain PVs are
  # printed for manual deletion; Delete-policy PVs are removed automatically.
  # on_failure = continue: PVC cleanup is best-effort — if the cluster or
  # namespace is already gone (e.g. force-deleted externally), a kubectl error
  # must not block the rest of `terraform destroy`.
  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.input.kubeconfig_path
    }
    command = "${path.module}/scripts/purge-stale-dsc-pvc.sh '${self.input.namespace}' '${self.input.dsc_name}' destroy"
  }

  depends_on = [kubernetes_namespace_v1.dsc_namespace]
}
##############################################################################
# Check for existing BRS agent namespaces (conflict detection)
##############################################################################

# If a brs-backup-agent-* namespace already exists on the cluster, it means
# the cluster is already registered to a BRS instance. We should not silently
# overwrite or re-attach the cluster to a new BRS instance, as this would
# fragment backup data across BRS instances and confuse customers.
# Exit early with a clear explanation of what the customer must do.
resource "terraform_data" "check_existing_registration" {
  input = {
    kubeconfig_path = data.ibm_container_cluster_config.cluster_config.config_file_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.input.kubeconfig_path
    }
    command = "${path.module}/scripts/check-existing-registration.sh"
  }

  depends_on = [data.ibm_container_cluster_config.cluster_config]
}



##############################################################################
# Purge stale DSC PVCs before Helm install
##############################################################################

# Orphaned PVCs from a failed install hold stale gandalf state and an expired
# token; re-mounting them crashes the DSC immediately. The script deletes them
# only when no live pod exists — upgrades are safe. Destroy-time PVC cleanup
# is handled by dsc_immutable_values (destroyed after helm_release).
resource "terraform_data" "purge_stale_dsc_pvc" {
  triggers_replace = {
    namespace          = kubernetes_namespace_v1.dsc_namespace.metadata[0].name
    registration_token = local.registration_token != null ? local.registration_token : ""
  }

  input = {
    namespace       = kubernetes_namespace_v1.dsc_namespace.metadata[0].name
    kubeconfig_path = data.ibm_container_cluster_config.cluster_config.config_file_path
    dsc_name        = var.dsc_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.input.kubeconfig_path
    }
    command = "${path.module}/scripts/purge-stale-dsc-pvc.sh '${self.input.namespace}' '${self.input.dsc_name}'"
  }

  depends_on = [
    kubernetes_namespace_v1.dsc_namespace,
    terraform_data.check_existing_registration
  ]
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
  atomic           = false # DSC docs §8: rollbacks are unsupported and can corrupt PVC state.
  cleanup_on_fail  = true

  values = [
    yamlencode({
      secrets = {
        registrationToken = local.registration_token != null ? local.registration_token : ""
      }
      # image.tag is intentionally omitted — the chart uses its AppVersion as the
      # default tag, which is pinned to the chart version in dsc_chart_uri.
      # DSC docs §6.1: "image.tag need not be supplied during helm install/upgrade".
      replicaCount     = var.dsc_replicas
      fullnameOverride = var.dsc_name
      resources = {
        limits = {
          cpu    = var.dsc_pod_cpu_limits
          memory = var.dsc_pod_memory_limits
        }
        requests = {
          cpu    = var.dsc_pod_cpu_requests
          memory = var.dsc_pod_memory_requests
        }
      }
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
        # Frozen at first apply — see dsc_immutable_values.
        storageClass = terraform_data.dsc_immutable_values.input.storage_class
      }
    })
  ]

  depends_on = [
    terraform_data.dsc_immutable_values,
    terraform_data.wait_for_dsc_node_ready,
    terraform_data.purge_stale_dsc_pvc,
    ibm_container_vpc_worker_pool.data_source_connector,
    kubernetes_namespace_v1.dsc_namespace,
    # Ensure the VPE Gateway is live before the DSC pod starts.
    # When create_brs_vpe = true, the VPEG is module.brs_vpe[0]; DSC traffic
    # routes to BRS via the VPEG private endpoint immediately on pod startup.
    # When create_brs_vpe = false (cross-account, VPEG managed externally),
    # module.brs_vpe has count = 0 so this dep is a no-op — safe in all configs.
    module.brs_vpe,
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

  # Collect pod, event, PVC, and node diagnostics when the Helm install fails.
  # on_failure = continue ensures output is visible even when helm times out.
  provisioner "local-exec" {
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = data.ibm_container_cluster_config.cluster_config.config_file_path
    }
    command = "${path.module}/scripts/dsc-helm-diagnostics.sh '${self.namespace}' '${local.dsc_storage_class}'"
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
    namespace = var.dsc_namespace
  }

  lifecycle {
    ignore_changes = [
      image_pull_secret,
      secret,
      metadata[0].annotations,
    ]
  }
  depends_on = [kubernetes_namespace_v1.dsc_namespace]
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

# Wait for DSC to stabilize after helm installation before source registration.
resource "time_sleep" "wait_for_dsc_stabilization" {
  depends_on = [helm_release.data_source_connector]

  # 10m observed minimum for the DSC gRPC tunnel to BRS to fully establish after
  # the pod passes Kubernetes readiness (/bifrost/readyz). The readiness probe only
  # confirms the HTTP server started — the BRS cluster-config protobin handshake
  # and reverse-tunnel setup take several additional minutes. Without this wait,
  # source_registration hits the BRS API before the DSC has connected, causing
  # RegisterProtectionSourceWithContext: Gateway Timeout (BRS internal 9-10 min limit).
  create_duration = "10m"
}

# On destroy this sends DELETE to BRS, permanently removing the connector identity.
# Correct for a full terraform destroy (PVCs also deleted).
# NOT correct for a temporary scale-down (kubectl scale ... --replicas=0): pods
# retain their identity and reconnect automatically when scaled back up — do not
# deregister. Because terraform destroy always deletes PVCs too, the destroy path
# here is always safe.
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
    time_sleep.wait_for_dsc_stabilization,
    time_sleep.brs_source_deregistration_wait,
    module.backup_recovery_instance,
  ]

  # service_name is an undocumented, provider-computed attribute. The provider
  # applies a default ("backup-recovery") at plan time but stores null in state,
  # so every re-plan shows a null -> "backup-recovery" diff. Because the field is
  # ForceNew, that spurious diff forces a full replacement on each apply (and
  # fails the post-apply consistency check). Ignore it so registration stays
  # stable.
  lifecycle {
    ignore_changes = [service_name]
  }
}

# BRS source deregistration is async on the backend. Without this sleep,
# DeleteDataSourceConnectionWithContext fails with "can't be deleted as it is
# being used by the source" because the connection is still referenced when
# the DSC connection cleanup script runs on the BRS instance side.
# destroy_duration fires between source_registration destruction and the
# namespace wait, giving BRS time to process the async deregistration.
# 20m: BRS backend globally releases the cluster endpoint registration only
# after full internal cleanup; 10m was not sufficient — consecutive runs on
# the same cluster hit "already registered to brs-backup-agent-<id>" errors.
resource "time_sleep" "brs_source_deregistration_wait" {
  depends_on       = [terraform_data.wait_before_helm_destroy]
  destroy_duration = "20m"
}

# Wait for namespace cleanup during destroy before destroying helm release.
# Keeps brsagent RBAC and token alive so BRS can use them to clean up
# brs-backup-agent-* namespaces via the DSC pod after source deregistration.
resource "terraform_data" "wait_before_helm_destroy" {
  depends_on = [
    helm_release.data_source_connector,
    kubernetes_cluster_role_binding_v1.brsagent_admin,
    kubernetes_secret_v1.brsagent_token,
  ]

  # This resource exists solely to run a destroy-time provisioner (namespace
  # cleanup) before the helm release is destroyed; it has no create/update
  # behavior, so it never needs to be replaced. Values needed by the destroy
  # provisioner are stored in input (available via self.input at destroy time).
  # No triggers_replace: a helm release update (e.g. the by-design registration
  # token rotation) would make helm_release.id "known after apply" and cascade
  # into a spurious replacement. An input change is only ever an in-place update
  # that runs no provisioner, so it is side-effect free.
  input = {
    kubeconfig_path = data.ibm_container_cluster_config.cluster_config.config_file_path
    dsc_namespace   = var.dsc_namespace
  }

  # self.input is wrapped in try() so the destroy provisioner stays safe when the
  # resource instance was created by an older module version that stored these
  # values in triggers_replace instead of input (in that case self.input is null
  # in state). An empty KUBECONFIG makes the script skip the namespace wait and
  # exit cleanly, which is the correct behaviour during that one-time migration.
  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/wait_for_namespace_cleanup.sh '${try(self.input.dsc_namespace, "ibm-brs-data-source-connector")}'"
    environment = {
      KUBECONFIG = try(self.input.kubeconfig_path, "")
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
    dsc_version   = var.dsc_chart_uri
  }

  create_duration = "10m"
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
  # Flatten protection sources up to 3 levels deep to create a map of object names
  # (namespaces, PVCs, etc.) to IDs — scoped to THIS cluster's registered source only.

  # Pre-compute the set of all node-level source IDs present in the current API response.
  all_known_source_ids = toset(flatten([
    for env in(try(data.ibm_backup_recovery_protection_sources.sources.protection_sources, []) != null ? data.ibm_backup_recovery_protection_sources.sources.protection_sources : []) :
    [for node in(env.nodes != null ? env.nodes : []) :
      tostring(node.protection_source[0].id)
      if node.protection_source != null && length(node.protection_source) > 0
    ]
  ]))

  filter_by_source_id = (
    ibm_backup_recovery_source_registration.source_registration.source_id != null &&
    contains(local.all_known_source_ids, tostring(ibm_backup_recovery_source_registration.source_registration.source_id))
  )

  all_env_nodes = flatten([
    for env in(try(data.ibm_backup_recovery_protection_sources.sources.protection_sources, []) != null ? data.ibm_backup_recovery_protection_sources.sources.protection_sources : []) :
    [for node in(env.nodes != null ? env.nodes : []) : node
      if !local.filter_by_source_id ||
      (node.protection_source != null &&
        length(node.protection_source) > 0 &&
      tostring(node.protection_source[0].id) == tostring(ibm_backup_recovery_source_registration.source_registration.source_id))
    ]
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
# Cancel running backup jobs before protection group deletion
##############################################################################

# Cancels any active backup run on each protection group during destroy.
# Must depend on the protection group so Terraform destroys this resource first,
# running the cancel provisioner before the provider attempts to delete the group.
resource "terraform_data" "cancel_pg_runs" {
  for_each = { for pg in var.protection_groups : pg.name => pg }

  input = {
    region              = local.brs_instance_region
    tenant              = local.brs_tenant_id
    brs_endpoint        = local.backup_recovery_instance_url
    protection_group_id = ibm_backup_recovery_protection_group.protection_group[each.key].id
  }

  triggers_replace = {
    api_key = sensitive(var.ibmcloud_api_key)
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}/scripts/cancel_pg_runs.sh '${self.input.region}' '${self.input.tenant}' '${self.input.protection_group_id}' '${self.input.brs_endpoint}'"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      IBMCLOUD_API_KEY = self.triggers_replace.api_key # pragma: allowlist secret
    }
  }

  depends_on = [ibm_backup_recovery_protection_group.protection_group]
}

##############################################################################
# Tag cluster with BRS instance information
##############################################################################

# Adds BRS tags to identify which instance is protecting this cluster.
# Set add_cluster_tags = false to prevent tag drift when cluster tags are managed externally.
resource "ibm_resource_tag" "cluster_brs_tag" {
  count    = var.add_cluster_tags ? 1 : 0
  provider = ibm.cluster

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
  count      = var.enable_auto_protect && var.auto_protect_policy_name != null ? 1 : 0

  input = {
    region              = local.brs_instance_region
    tenant              = local.brs_tenant_id
    protection_group_id = ibm_backup_recovery_source_registration.source_registration.kubernetes_params[0].auto_protect_config[0].protection_group_id
    brs_endpoint        = local.backup_recovery_instance_url
    api_key             = sensitive(var.ibmcloud_api_key)
  }

  triggers_replace = {
    api_key = sensitive(var.ibmcloud_api_key)
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}/scripts/delete_auto_protect_pg.sh '${self.input.region}' '${self.input.tenant}' '${self.input.protection_group_id}' '${self.input.brs_endpoint}'"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      IBMCLOUD_API_KEY = self.triggers_replace.api_key # pragma: allowlist secret
    }
  }
}


##############################################################################
# Immediate Backup Trigger for Recovery Mode
##############################################################################

# Small delay to ensure protection group is fully registered before triggering backup
resource "time_sleep" "wait_for_pg_registration" {
  count = local.deploy_recovery ? 1 : 0

  depends_on = [
    ibm_backup_recovery_protection_group.protection_group,
    time_sleep.wait_for_source_discovery
  ]

  create_duration = "90s" # Increased to 90s to match solution wrapper

  triggers = {
    protection_group_ids = join(",", [for pg in ibm_backup_recovery_protection_group.protection_group : pg.id])
  }
}

# Extract numeric protection group IDs for API calls
locals {
  # Convert full PG ID format (clusterid/::timestamp:id:id) to numeric format (timestamp:id:id)
  # Example: "5n3kwor5cb/::8009179080677672:1753125047518:126734" -> "8009179080677672:1753125047518:126734"
  numeric_pg_ids = local.deploy_recovery ? {
    for pg_name, pg_resource in ibm_backup_recovery_protection_group.protection_group :
    pg_name => split("::", pg_resource.id)[1]
  } : {}
}

# Trigger an immediate on-demand backup run for each protection group in recovery mode,
# but only if BRS has not already started one automatically (which it does as soon as a
# protection group is registered against an active policy).
# Blindly firing a second kRegular run while a CloudArchiveDirect archival task is in
# progress causes: "CloudArchiveDirect job has an active archival task for primary target".
resource "terraform_data" "trigger_backup_run" {
  for_each = local.deploy_recovery ? { for pg in var.protection_groups : pg.name => pg } : {}

  depends_on = [
    ibm_backup_recovery_protection_group.protection_group,
    time_sleep.wait_for_source_discovery,
    time_sleep.wait_for_pg_registration,
    terraform_data.install_dependencies
  ]

  input = {
    url                 = "https://${local.backup_recovery_instance_url}"
    tenant              = local.brs_tenant_id
    endpoint_type       = var.brs_endpoint_type
    instance_id         = local.brs_instance_guid
    protection_group_id = ibm_backup_recovery_protection_group.protection_group[each.key].id
    api_key             = sensitive(var.ibmcloud_api_key)
    binaries_path       = local.binaries_path
  }

  triggers_replace = {
    protection_group_id = ibm_backup_recovery_protection_group.protection_group[each.key].id
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/trigger_backup_run.sh '${self.input.url}' '${self.input.tenant}' '${self.input.endpoint_type}' '${self.input.instance_id}' '${self.input.protection_group_id}'"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key # pragma: allowlist secret
    }
  }
}

##############################################################################
# Active Backup Polling (Replaces Blind Wait)
##############################################################################

# Actively poll for backup completion instead of blind waiting
# This script checks backup status every 30 seconds until completion or timeout
resource "terraform_data" "wait_for_backup_run" {
  for_each = local.deploy_recovery ? { for pg in var.protection_groups : pg.name => pg } : {}

  depends_on = [
    ibm_backup_recovery_protection_group.protection_group,
    time_sleep.wait_for_source_discovery,
    terraform_data.trigger_backup_run,
    terraform_data.install_dependencies
  ]

  input = {
    url                   = "https://${local.backup_recovery_instance_url}"
    tenant                = local.brs_tenant_id
    endpoint_type         = var.brs_endpoint_type
    instance_id           = local.brs_instance_guid
    protection_group_id   = ibm_backup_recovery_protection_group.protection_group[each.key].id
    api_key               = sensitive(var.ibmcloud_api_key)
    timeout_minutes       = var.backup_run_poll_timeout_minutes
    poll_interval_seconds = var.backup_run_poll_interval_seconds
    binaries_path         = local.binaries_path
  }

  triggers_replace = {
    protection_group_id   = ibm_backup_recovery_protection_group.protection_group[each.key].id
    timeout_minutes       = tostring(var.backup_run_poll_timeout_minutes)
    poll_interval_seconds = tostring(var.backup_run_poll_interval_seconds)
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/wait_for_backup_run.sh '${self.input.url}' '${self.input.tenant}' '${self.input.endpoint_type}' '${self.input.instance_id}' '${self.input.protection_group_id}' '${self.input.timeout_minutes}' '${self.input.poll_interval_seconds}' '${self.input.binaries_path}'"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      IBMCLOUD_API_KEY = self.input.api_key
    }
  }
}

##############################################################################
# Query Protection Group Runs (Snapshot Discovery)
##############################################################################

# Data source to discover completed backup snapshots after polling confirms they exist
data "ibm_backup_recovery_protection_group_runs" "backup_runs" {
  for_each = local.deploy_recovery ? { for pg in var.protection_groups : pg.name => pg } : {}

  x_ibm_tenant_id        = local.brs_tenant_id
  protection_group_id    = local.numeric_pg_ids[each.key]
  endpoint_type          = var.brs_endpoint_type
  instance_id            = local.brs_instance_guid
  region                 = local.brs_instance_region
  include_object_details = true
  archival_run_status    = ["Succeeded", "SucceededWithWarning"]

  depends_on = [
    terraform_data.wait_for_backup_run,
    ibm_backup_recovery_protection_group.protection_group
  ]
}

# Local to extract latest successful snapshot IDs per protection group
locals {
  # Map of protection group name to latest successful snapshot
  latest_snapshots = local.deploy_recovery ? {
    for pg_name, runs in data.ibm_backup_recovery_protection_group_runs



    .backup_runs : pg_name => (
      length(try(runs.runs, [])) > 0 ? (
        try(runs.runs[0].local_backup_info[0].snapshot_info[0].snapshot_id, try(runs.runs[0].id, null))
      ) : null
    )
  } : {}

  # Determine target cluster details based on recovery mode
  # For cross-cluster recovery, the target cluster must be pre-registered with the same BRS instance
  target_cluster_id = var.recovery_mode == "cross-cluster" ? var.target_cluster_id : var.cluster_id
}

##############################################################################
# Restore the backups to Same or Different Cluster
##############################################################################

resource "ibm_backup_recovery" "recover_snapshot" {
  for_each = local.deploy_recovery ? { for recovery in var.recoveries : recovery.name => recovery } : {}

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
    terraform_data.wait_for_backup_run,
    data.ibm_backup_recovery_protection_group_runs.backup_runs,
    ibm_backup_recovery_protection_group.protection_group,
    ibm_backup_recovery_source_registration.source_registration
  ]

  lifecycle {
    precondition {
      condition     = length(local.latest_snapshots) > 0
      error_message = <<-EOT
        No backup snapshots found. Recovery cannot proceed without completed backups.
        The module actively polls for backup completion (up to backup_run_poll_timeout_minutes).
        Either:
        1. Increase backup_run_poll_timeout_minutes to allow more time for backups to complete
        2. Ensure protection groups have run at least one successful backup before recovery
      EOT
    }

    precondition {
      condition = (
        var.recovery_mode == "same-cluster" ||
        (var.recovery_mode == "cross-cluster" && var.target_cluster_id != null && var.target_cluster_resource_group_id != null)
      )
      error_message = "For cross-cluster recovery, both target_cluster_id and target_cluster_resource_group_id must be provided."
    }
  }

}
