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

  # vpc_id: from new VPC resource when creating a cluster, or from the
  # user-supplied variable when using an existing cluster.
  vpc_id = var.cluster_name_id != null ? var.vpc_id : ibm_is_vpc.vpc[0].id

  # vpc_subnets: built statically from var.prefix / var.region so the
  # for_each keys in the VPEG module are known at plan time.
  # When using an existing cluster the user must supply vpc_id; the
  # existing-subnets data source discovers subnets by VPC.
  vpc_subnets = var.cluster_name_id != null ? [for s in data.ibm_is_subnets.existing_subnets[0].subnets : {
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

# Discover subnets in the existing cluster's VPC for VPEG reserved IPs.
data "ibm_is_subnets" "existing_subnets" {
  count    = var.cluster_name_id != null ? 1 : 0
  provider = ibm.source
  vpc      = var.vpc_id
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
# BRS backup & recovery module  (default provider = target account for BRS
#   resources; source provider passed for cluster / VPC / VPEG resources)
#
# Design note
# -----------
# The root module (../.. ) uses the DEFAULT ibm provider for ALL resources:
#   - ibm_resource_instance / ibm_backup_recovery_* → must be target account ✓
#   - ibm_container_vpc_cluster data sources          → must be source account ✗
#   - ibm_is_virtual_endpoint_gateway (VPEG)          → must be source account ✗
#
# Because a single module call cannot fan-out to two different IBM provider
# aliases, we split the concerns:
#   - The root module runs with the DEFAULT provider (target account).
#     We pass brs_source_account_id = null so the module does NOT try to
#     create the S2S auth (we create it above, explicitly in the target
#     account).  create_brs_vpe = true is still passed so the VPEG is
#     created — BUT the VPEG resource inside the module also uses the
#     default provider.  This means the VPEG is created in the TARGET
#     account's VPC context, which is wrong for true cross-account.
#
# WORKAROUND applied in this example:
#   We set create_brs_vpe = false on the root module and create the VPEG
#   directly below using ibm.source, pointing it at the BRS CRN output
#   from the module.  The S2S auth (above) is created separately in the
#   target account.
##############################################################################

module "backup_recovery" {
  source = "../.."
  # default ibm provider (target account) for BRS resources

  depends_on = [time_sleep.wait_operators]

  # ---- Cluster (source account) ----
  # The root module reads these via ibm_container_vpc_cluster data sources.
  # Since the default provider is the target account, we must ensure the
  # cluster is accessible from the target account API key, OR use an
  # existing cluster whose ID is known.  For simplicity this example
  # always provisions or references a cluster in the source account and
  # passes the cluster ID (already resolved above via ibm.source).
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
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_instance_name         = "${var.prefix}-brs"
  brs_connection_name       = "${var.prefix}-brs-connection"
  brs_create_new_connection = true

  # ---- Endpoint settings ----
  # Use public endpoint so Terraform (running from workstation or CI) can
  # reach the target-account BRS API.  DSC traffic routes via the VPEG.
  brs_endpoint_type = "public"

  # VPEG is created separately below (ibm.source) to place it in the
  # correct source-account VPC.  The S2S auth is created above.
  create_brs_vpe        = false
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

##############################################################################
# VPEG  (source account — the VPC that hosts the IKS cluster)
#
# The VPEG targets the BRS CRN from the target account.  The S2S IAM
# authorization policy (created above in the target account) allows the
# VPEG to resolve and connect to the cross-account BRS service endpoint.
#
# Reserved IP name is built from var.prefix and var.region so the
# for_each key is statically known at plan time.
##############################################################################

module "brs_vpe" {
  source  = "terraform-ibm-modules/vpe-gateway/ibm"
  version = "5.3.5"
  providers = {
    ibm = ibm.source
  }

  # region is the cluster region — always known at plan time.
  # prefix and vpc_name only affect naming when vpe_name is null; since
  # vpe_name is always provided explicitly both are harmless labels.
  region            = var.region
  prefix            = "brs"
  vpc_name          = var.prefix
  vpc_id            = local.vpc_id
  subnet_zone_list  = local.vpc_subnets
  resource_group_id = module.source_resource_group.resource_group_id

  # Attach to the kube-vpegw-<vpc-id> SG IKS creates on every VPC cluster.
  security_group_ids = [data.ibm_is_security_group.kube_vpeg_sg.id]

  # vpe_name is always explicit so the for_each map key is a static
  # string known at plan time (not derived from vpc_id or BRS CRN).
  cloud_service_by_crn = [
    {
      crn          = module.backup_recovery.brs_instance_crn
      service_name = "backup-recovery"
      vpe_name     = "${var.prefix}-brs-connection-vpe"
    }
  ]

  depends_on = [module.brs_s2s_auth]
}

# Fetch the IKS-managed kube-vpegw security group from the source account.
data "ibm_is_security_group" "kube_vpeg_sg" {
  provider = ibm.source
  name     = "kube-vpegw-${local.vpc_id}"

  depends_on = [ibm_container_vpc_cluster.vpc_cluster]
}
