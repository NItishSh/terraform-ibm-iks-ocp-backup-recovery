##############################################################################
# backup-recovery-with-vpe example
#
# Demonstrates how to protect an IKS/ROKS cluster using the BRS module
# with traffic routed through a Virtual Private Endpoint Gateway (VPEG).
#
# Two deployment patterns are supported:
#
#   SAME-ACCOUNT  (brs_source_account_id = null)
#     The cluster VPC and the BRS instance are in the same IBM Cloud account.
#     A VPEG is created in the cluster VPC targeting the BRS instance CRN.
#     No S2S IAM authorization is needed.
#
#   CROSS-ACCOUNT (brs_source_account_id = "<source-account-id>")
#     The cluster lives in the SOURCE account; BRS lives in the TARGET account.
#     Apply this example from the TARGET account (where Terraform has credentials
#     for the BRS instance).  An S2S IAM authorization policy is created
#     allowing the VPC Infrastructure endpoint-gateway in the source account to
#     target the BRS instance.  The VPEG is created in the source-account VPC
#     using a cross-account provider alias.
#
# Prerequisites:
#   - An IKS or ROKS VPC-Gen2 cluster already provisioned
#   - Subnet list for the cluster VPC (one subnet per zone)
#   - For cross-account: Terraform has credentials for both accounts
##############################################################################

##############################################################################
# Resource group
##############################################################################

module "resource_group" {
  source                       = "terraform-ibm-modules/resource-group/ibm"
  version                      = "1.6.0"
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

##############################################################################
# Lookup VPC and its subnets from the cluster
##############################################################################

data "ibm_is_subnets" "subnets" {
  vpc = var.vpc_id
}

locals {
  # Build subnet_zone_list in the shape expected by terraform-ibm-vpe-gateway.
  vpc_subnets = [for s in data.ibm_is_subnets.subnets.subnets : {
    name = s.name
    id   = s.id
    zone = s.zone
  }]
}

##############################################################################
# BRS Backup & Recovery with VPEG connectivity
##############################################################################

module "backup_recovery" {
  source = "../.."

  # ---- Cluster ----
  cluster_id                = var.cluster_id
  cluster_resource_group_id = module.resource_group.resource_group_id
  kube_type                 = var.kube_type
  connection_env_type       = var.kube_type == "openshift" ? "kROKSVpc" : "kIksVpc"
  ibmcloud_api_key          = var.ibmcloud_api_key
  region                    = var.region

  # ---- BRS instance ----
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_instance_name         = "${var.prefix}-brs"
  brs_connection_name       = "${var.prefix}-connection"

  # ---- VPEG connectivity ----
  # Route BRS traffic through the private backbone via VPEG.
  # brs_endpoint_type = "vpe" makes the module compute the BRS endpoint as
  # <guid>.private.<region>.backup-recovery.cloud.ibm.com which is the DNS
  # name resolved by the VPEG reserved IPs inside the cluster VPC.
  brs_endpoint_type     = "vpe"
  create_brs_vpe        = true
  vpc_id                = var.vpc_id
  vpc_subnets           = local.vpc_subnets
  brs_source_account_id = var.brs_source_account_id # null = same-account

  # ---- Protection ----
  policies = [
    {
      name              = "${var.prefix}-daily-policy"
      create_new_policy = true
      schedule = {
        unit         = "Days"
        day_schedule = { frequency = 1 }
      }
      retention = {
        unit     = "Weeks"
        duration = 4
      }
      use_default_backup_target = true
    }
  ]

  protection_groups = [
    {
      name        = "${var.prefix}-pg"
      policy_name = "${var.prefix}-daily-policy"
      description = "Daily backup of cluster workloads via VPE"
      priority    = "kMedium"
    }
  ]

  resource_tags = var.resource_tags
  access_tags   = var.access_tags
}
