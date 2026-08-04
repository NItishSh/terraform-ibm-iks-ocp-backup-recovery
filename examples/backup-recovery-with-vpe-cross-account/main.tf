##############################################################################
# backup-recovery-with-vpe-cross-account example
#
# Demonstrates BRS VPE connectivity across two IBM Cloud accounts:
#
#   SOURCE account  (source_ibmcloud_api_key)
#     - IKS VPC cluster  (created or existing)
#     - VPC + subnet + public gateway  (created when cluster_name_id = null)
#     - VPE Gateway  (brs-vpe-brs-connection-vpe)  targeting the BRS CRN
#
#   TARGET account  (ibmcloud_api_key / default provider)
#     - BRS instance  (new or existing)
#     - BRS data-source connection + registration token
#     - S2S IAM authorization policy  (endpoint-gateway in source account
#       → BRS instance in target account)
#
# Apply order
# -----------
# Both provider aliases share a single terraform apply.  Terraform
# resolves the dependency graph so the BRS instance + S2S auth are
# created before the VPEG is attached, and the VPEG is live before the
# DSC Helm chart is deployed.
#
# After apply, exec into the DSC pod and run:
#   getent hosts <brs_private_hostname>
# The result should resolve to the VPEG reserved IP, confirming that
# DSC→BRS traffic routes through the IBM private backbone.
##############################################################################

locals {
  brs_region = var.brs_region != null ? var.brs_region : var.region

  # cluster_id: existing cluster name/ID or newly created cluster ID.
  cluster_id = var.cluster_name_id != null ? data.ibm_container_vpc_cluster.vpc_cluster_data[0].name : ibm_container_vpc_cluster.vpc_cluster[0].id

  # Flatten all subnet IDs out of worker_pools -> zones -> subnets for an
  # existing cluster. These IDs come from the cluster data source and are
  # known at plan time, so the for_each count in ibm_is_subnet is static.
  existing_cluster_subnet_ids = var.cluster_name_id != null ? flatten(
    data.ibm_container_vpc_cluster.vpc_cluster_data[0].worker_pools[*].zones[*].subnets[*].id
  ) : []

  # Number of per-subnet lookups to perform for existing clusters.
  existing_subnet_lookup_count = var.cluster_name_id != null ? length(local.existing_cluster_subnet_ids) : 0

  # vpc_id: from new VPC resource when creating a cluster, or resolved via
  # the first per-subnet lookup of the existing cluster (no user input needed).
  vpc_id = var.cluster_name_id != null ? data.ibm_is_subnet.cluster_subnet[0].vpc : ibm_is_vpc.vpc[0].id

  # vpc_subnets: for a new cluster, one static subnet from the IKS resource.
  # For an existing cluster, built from the per-subnet lookups — all keys
  # (name, id, zone) are known at apply time; the for_each key in module.brs_vpe
  # is set explicitly via vpe_name so plan is still deterministic.
  vpc_subnets = var.cluster_name_id != null ? [for s in data.ibm_is_subnet.cluster_subnet : {
    name = s.name
    id   = s.id
    zone = s.zone
    }] : [{
    name = "${var.prefix}-subnet-1"
    id   = ibm_is_subnet.subnet_zone_1[0].id
    zone = "${var.region}-1"
  }]
}

##############################################################################
# Resource groups
##############################################################################

# Source-account resource group (cluster, VPC, VPEG).
module "source_resource_group" {
  source  = "terraform-ibm-modules/resource-group/ibm"
  version = "1.6.0"
  providers = {
    ibm = ibm.source
  }
  resource_group_name          = var.source_resource_group == null ? "${var.prefix}-source-rg" : null
  existing_resource_group_name = var.source_resource_group
}

# Target-account resource group (BRS instance).
module "target_resource_group" {
  source  = "terraform-ibm-modules/resource-group/ibm"
  version = "1.6.0"
  # uses default ibm provider (target account)
  resource_group_name          = var.target_resource_group == null ? "${var.prefix}-target-rg" : null
  existing_resource_group_name = var.target_resource_group
}

##############################################################################
# Source-account VPC + subnet + gateway  (created when cluster_name_id = null)
##############################################################################

resource "ibm_is_vpc" "vpc" {
  count    = var.cluster_name_id == null ? 1 : 0
  provider = ibm.source

  name                      = "${var.prefix}-vpc"
  resource_group            = module.source_resource_group.resource_group_id
  address_prefix_management = "auto"
  tags                      = var.resource_tags
}

resource "ibm_is_public_gateway" "gateway" {
  count    = var.cluster_name_id == null ? 1 : 0
  provider = ibm.source

  name           = "${var.prefix}-gateway-1"
  vpc            = ibm_is_vpc.vpc[0].id
  resource_group = module.source_resource_group.resource_group_id
  zone           = "${var.region}-1"
}

resource "ibm_is_subnet" "subnet_zone_1" {
  count    = var.cluster_name_id == null ? 1 : 0
  provider = ibm.source

  name                     = "${var.prefix}-subnet-1"
  vpc                      = ibm_is_vpc.vpc[0].id
  resource_group           = module.source_resource_group.resource_group_id
  zone                     = "${var.region}-1"
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.gateway[0].id
}

##############################################################################
# Source-account IKS cluster  (created when cluster_name_id = null)
##############################################################################

resource "ibm_container_vpc_cluster" "vpc_cluster" {
  count    = var.cluster_name_id == null ? 1 : 0
  provider = ibm.source

  name                                = "${var.prefix}-cluster"
  vpc_id                              = ibm_is_vpc.vpc[0].id
  flavor                              = "bx2.4x16"
  force_delete_storage                = true
  resource_group_id                   = module.source_resource_group.resource_group_id
  worker_count                        = 2
  disable_outbound_traffic_protection = true
  tags                                = var.resource_tags

  zones {
    subnet_id = ibm_is_subnet.subnet_zone_1[0].id
    name      = "${var.region}-1"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

##############################################################################
# Existing cluster lookup  (when cluster_name_id is provided)
##############################################################################

data "ibm_container_vpc_cluster" "vpc_cluster_data" {
  count    = var.cluster_name_id != null ? 1 : 0
  provider = ibm.source

  name              = var.cluster_name_id
  resource_group_id = module.source_resource_group.resource_group_id
}

# Look up every subnet of the existing cluster individually.
# The IDs come from worker_pools splat and are known at plan time, so the
# count is static and avoids the unknown-at-plan-time problem of ibm_is_subnets.
data "ibm_is_subnet" "cluster_subnet" {
  count      = local.existing_subnet_lookup_count
  provider   = ibm.source
  identifier = local.existing_cluster_subnet_ids[count.index]
}

##############################################################################
# Cluster kubeconfig  (source account, used by kubernetes + helm providers)
##############################################################################

data "ibm_container_cluster_config" "cluster_config" {
  provider = ibm.source

  cluster_name_id   = local.cluster_id
  resource_group_id = module.source_resource_group.resource_group_id
  admin             = true
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
}

resource "time_sleep" "wait_operators" {
  depends_on      = [data.ibm_container_cluster_config.cluster_config]
  create_duration = "60s"
}

##############################################################################
# S2S IAM authorization policy  (target account)
#
# Allows the VPC Infrastructure "endpoint-gateway" service in the source
# account to access the BRS instance in the target account.  This policy
# must exist before the VPEG is attached so the VPEG can resolve the BRS
# CRN across account boundaries.
#
# Uses the terraform-ibm-modules/s2s-auth module which creates an
# ibm_iam_authorization_policy resource via the default IBM provider
# (= target account here).
##############################################################################

module "brs_s2s_auth" {
  source  = "terraform-ibm-modules/s2s-auth/ibm"
  version = "2.3.1"
  # default ibm provider = target account

  enable_cbr = false

  service_map = {
    "brs-vpe-s2s" = {
      # Source side: VPC Infrastructure / endpoint-gateway in the SOURCE account
      source_service_name       = "is"
      source_resource_type      = "endpoint-gateway"
      source_service_account_id = var.source_account_id

      # Target side: this specific BRS instance in the TARGET account
      target_service_name         = "backup-recovery"
      target_resource_instance_id = module.backup_recovery.brs_instance_guid

      roles       = ["Viewer"]
      description = "Cross-account: VPC endpoint-gateway (acct ${var.source_account_id}) → BRS instance (acct target)"
    }
  }

  depends_on = [module.backup_recovery]
}

##############################################################################
# BRS backup & recovery module  (default provider = target account)
#
# Design note — why VPEG and S2S auth live outside the root module
# -----------------------------------------------------------------
# The root module (../.. ) uses a SINGLE ibm provider alias for every
# resource it creates:
#   - ibm_resource_instance / ibm_backup_recovery_* → target account  ✓
#   - ibm_container_vpc_cluster data sources         → source account  ✗
#   - ibm_is_virtual_endpoint_gateway (VPEG)         → source account  ✗
#
# A Terraform module call cannot fan resources out across two provider
# aliases, so we split responsibilities:
#
#   Root module (../..):
#     create_brs_vpe = false   — no VPEG created inside the module
#     brs_source_account_id = null  — no S2S auth inside the module
#     Default ibm provider (target account) creates BRS instance +
#     connection + protection policy.
#
#   This example (outside the module):
#     module.brs_s2s_auth  — creates the cross-account IAM policy
#                            using the default ibm provider (target account)
#     module.brs_vpe       — creates the VPEG in the source-account VPC
#                            using ibm.source provider
##############################################################################

module "backup_recovery" {
  source = "../.."
  # BRS resources (ibm_backup_recovery_*, ibm_resource_instance, S2S policy)
  # use the default ibm provider → target (BRS) account.
  # Cluster/VPC resources (ibm_container_*, ibm_is_*, ibm_resource_tag on cluster)
  # use ibm.cluster → source account, via the ibm.source alias defined in provider.tf.
  providers = {
    ibm         = ibm        # target account  — BRS instance, connection, S2S auth
    ibm.cluster = ibm.source # source account  — cluster data sources, DSC worker pool, tags
  }

  depends_on = [time_sleep.wait_operators]

  # ---- Cluster (source account) ----
  cluster_id                   = local.cluster_id
  cluster_resource_group_id    = module.source_resource_group.resource_group_id
  cluster_config_endpoint_type = var.cluster_config_endpoint_type
  kube_type                    = "kubernetes"
  connection_env_type          = "kIksVpc"
  ibmcloud_api_key             = var.ibmcloud_api_key # target account key used by scripts
  region                       = local.brs_region
  dsc_storage_class            = "ibmc-vpc-block-metro-5iops-tier"
  dsc_worker_pool_zones        = 1
  add_dsc_rules_to_cluster_sg  = false
  enable_auto_protect          = false

  # ---- BRS instance (target account) ----
  # brs_resource_group_id points at the TARGET-account resource group so the
  # BRS instance is created in the correct account. Without this, the root
  # module would fall back to cluster_resource_group_id which belongs to the
  # source account, causing the BRS instance to land in the wrong account.
  brs_resource_group_id     = module.target_resource_group.resource_group_id
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_instance_name         = "${var.prefix}-brs"
  brs_connection_name       = "${var.prefix}-brs-connection"
  brs_create_new_connection = true

  # ---- Endpoint settings ----
  # Use public endpoint so Terraform (running from workstation or CI) can
  # reach the target-account BRS API.  DSC traffic routes via the VPEG.
  brs_endpoint_type = "public"

  # VPEG is created by the root module using provider = ibm.cluster (= ibm.source),
  # which places it in the source-account VPC.  S2S auth is created above.
  create_brs_vpe        = true
  brs_source_account_id = null

  # ---- Backup policy ----
  policies = [
    {
      name              = "${var.prefix}-retention"
      create_new_policy = true
      schedule = {
        unit         = "Days"
        day_schedule = { frequency = 1 }
      }
      retention = {
        unit     = "Days"
        duration = 30
      }
      use_default_backup_target = true
    }
  ]

  resource_tags = var.resource_tags
  access_tags   = var.access_tags
}

