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

  # vpc_id / vpc_subnets: used by module.brs_vpe and data.ibm_is_security_group.kube_vpeg_sg.
  # For a NEW cluster (cluster_name_id = null) these come from the ibm_is_vpc /
  # ibm_is_subnet resources created earlier in this file — always known at plan time.
  # NOTE: the existing-cluster path (cluster_name_id != null) is not supported for
  # automated VPEG creation in this example because ibm_container_vpc_cluster does
  # not expose vpc_id as a top-level attribute; supply vpc_id / vpc_subnets explicitly
  # via variables if you need to bring your own cluster.
  vpc_id = ibm_is_vpc.vpc[0].id
  vpc_subnets = [
    {
      name = ibm_is_subnet.subnet_zone_1[0].name
      id   = ibm_is_subnet.subnet_zone_1[0].id
      zone = ibm_is_subnet.subnet_zone_1[0].zone
    }
  ]
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
  # No explicit depends_on — the reference to module.backup_recovery.brs_instance_guid
  # already creates an implicit dependency on the BRS instance output.
  # An explicit depends_on = [module.backup_recovery] would force waiting for the
  # ENTIRE module (including the VPEG that hasn't been created yet), deadlocking the apply.
}

##############################################################################
# BRS backup & recovery module  (default provider = target account)
#
# Design note — resource ordering for cross-account VPEG
# -------------------------------------------------------
# The VPEG requires an S2S IAM auth policy to exist BEFORE it is created,
# because VPC resolves the BRS service CRN across account boundaries at
# VPEG creation time.  Without the policy, the API returns:
#   "Could not find service" (HTTP 400)
#
# The root module cannot enforce this ordering internally when the S2S auth
# is created outside the module, so we split responsibilities:
#
#   module.backup_recovery  (create_brs_vpe = false)
#     Default ibm provider (target account):
#       BRS instance, data-source connection, protection policy.
#     ibm.cluster provider (source account):
#       cluster data sources, DSC worker pool, Helm chart, source registration.
#
#   module.brs_s2s_auth  (this file, target account)
#     Cross-account IAM auth policy.
#     Implicitly depends on module.backup_recovery.brs_instance_guid.
#     No explicit depends_on needed — the reference is enough.
#
#   data.ibm_is_security_group.kube_vpeg_sg  (this file, source account)
#     Reads the kube-vpegw-<vpc-id> SG that IKS creates on every VPC cluster.
#
#   module.brs_vpe  (this file, source account via ibm.source provider)
#     VPEG creation.  depends_on = [module.brs_s2s_auth] enforces that S2S
#     auth exists before VPC attempts to resolve the BRS CRN cross-account.
##############################################################################

module "backup_recovery" {
  source = "../.."
  # BRS resources (ibm_backup_recovery_*, ibm_resource_instance)
  # use the default ibm provider → target (BRS) account.
  # Cluster/VPC resources (ibm_container_*, ibm_is_*, ibm_resource_tag on cluster)
  # use ibm.cluster → source account, via the ibm.source alias defined in provider.tf.
  providers = {
    ibm         = ibm        # target account  — BRS instance, connection
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

  # VPEG is created OUTSIDE this module call (see module.brs_vpe below) so
  # the S2S auth policy can be enforced to exist before VPC resolves the BRS
  # CRN cross-account.  Setting create_brs_vpe = false here skips the VPEG
  # and the kube-vpegw SG lookup inside the root module.
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
# kube-vpegw security group lookup  (source account)
#
# IKS automatically creates a security group named kube-vpegw-<vpc-id> on
# every VPC cluster.  It is pre-configured to allow cluster worker nodes to
# reach VPE targets.  We attach the VPEG to this SG so no extra rules are
# needed.
##############################################################################

data "ibm_is_security_group" "kube_vpeg_sg" {
  provider = ibm.source
  name     = "kube-vpegw-${local.vpc_id}"
  depends_on = [
    ibm_container_vpc_cluster.vpc_cluster,
    data.ibm_container_vpc_cluster.vpc_cluster_data,
  ]
}

##############################################################################
# BRS Virtual Private Endpoint Gateway  (source account)
#
# Created AFTER module.brs_s2s_auth so the IAM policy exists before VPC
# resolves the BRS service CRN cross-account.
##############################################################################

module "brs_vpe" {
  source  = "terraform-ibm-modules/vpe-gateway/ibm"
  version = "5.3.5"
  providers = {
    ibm = ibm.source # VPEG lives in the source-account VPC
  }

  region            = var.region
  prefix            = var.prefix
  vpc_name          = local.vpc_id
  vpc_id            = local.vpc_id
  subnet_zone_list  = local.vpc_subnets
  resource_group_id = module.source_resource_group.resource_group_id

  security_group_ids = [data.ibm_is_security_group.kube_vpeg_sg.id]

  cloud_service_by_crn = [
    {
      crn          = module.backup_recovery.brs_instance_crn
      service_name = "backup-recovery"
      # Static string key — must not be derived from unknown-at-plan-time values.
      vpe_name = "${var.prefix}-brs-connection-vpe"
    }
  ]

  # S2S auth MUST exist before VPC can resolve the BRS CRN cross-account.
  depends_on = [module.brs_s2s_auth]
}
