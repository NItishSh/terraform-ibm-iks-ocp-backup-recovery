##############################################################################
# backup-recovery-with-vpe example
#
# Demonstrates BRS module with Virtual Private Endpoint Gateway (VPEG)
# connectivity — traffic between the DSC pods and the BRS instance travels
# over the IBM private backbone instead of the public internet.
#
# Cluster provisioning follows the same pattern as the kubernetes and
# openshift examples: set cluster_name_id = null (default) to have this
# example create a new VPC + IKS cluster, or provide an existing cluster ID.
#
# Two BRS connectivity patterns are shown:
#
#   SAME-ACCOUNT  (brs_source_account_id = null, default)
#     Cluster VPC and BRS instance are in the same IBM Cloud account.
#     A VPEG is created in the VPC targeting the BRS instance CRN.
#     No S2S IAM authorization is required.
#
#   CROSS-ACCOUNT (brs_source_account_id = "<source-account-id>")
#     Cluster is in the SOURCE account; BRS is in the TARGET account.
#     Apply with credentials for the TARGET (BRS) account.
#     An S2S IAM authorization policy is created allowing the VPC
#     Infrastructure endpoint-gateway in the source account to target
#     the BRS instance. The VPEG is created in the source-account VPC.
##############################################################################

locals {
  # cluster_id resolves to the newly-created cluster ID or the existing one.
  cluster_id = var.cluster_name_id != null ? data.ibm_container_vpc_cluster.vpc_cluster_data[0].name : ibm_container_vpc_cluster.vpc_cluster[0].id

  # When a NEW cluster is created by this example, auto-discovery in the root
  # module cannot read worker-pool subnet IDs until after the cluster apply.
  # Pass the subnet explicitly so ibm_is_subnet count is always known at plan time.
  # For an existing cluster (cluster_name_id != null), leave both as null/[] so
  # the root module auto-discovers them from the cluster API.
  explicit_vpc_id = var.cluster_name_id == null ? ibm_is_vpc.vpc[0].id : null
  explicit_vpc_subnets = var.cluster_name_id == null ? [
    {
      name = ibm_is_subnet.subnet_zone_1[0].name
      id   = ibm_is_subnet.subnet_zone_1[0].id
      zone = ibm_is_subnet.subnet_zone_1[0].zone
    }
  ] : []
}

##############################################################################
# Resource Group
##############################################################################

module "resource_group" {
  source                       = "terraform-ibm-modules/resource-group/ibm"
  version                      = "1.6.0"
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

##############################################################################
# VPC + Subnet + Public Gateway  (only when creating a new cluster)
##############################################################################

resource "ibm_is_vpc" "vpc" {
  count                     = var.cluster_name_id == null ? 1 : 0
  name                      = "${var.prefix}-vpc"
  resource_group            = module.resource_group.resource_group_id
  address_prefix_management = "auto"
  tags                      = var.resource_tags
}

resource "ibm_is_public_gateway" "gateway" {
  count          = var.cluster_name_id == null ? 1 : 0
  name           = "${var.prefix}-gateway-1"
  vpc            = ibm_is_vpc.vpc[0].id
  resource_group = module.resource_group.resource_group_id
  zone           = "${var.region}-1"
}

resource "ibm_is_subnet" "subnet_zone_1" {
  count                    = var.cluster_name_id == null ? 1 : 0
  name                     = "${var.prefix}-subnet-1"
  vpc                      = ibm_is_vpc.vpc[0].id
  resource_group           = module.resource_group.resource_group_id
  zone                     = "${var.region}-1"
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.gateway[0].id
}

##############################################################################
# IKS VPC Cluster  (only when creating a new cluster)
##############################################################################

resource "ibm_container_vpc_cluster" "vpc_cluster" {
  count                = var.cluster_name_id == null ? 1 : 0
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

##############################################################################
# Existing cluster lookup  (only when cluster_name_id is provided)
##############################################################################

data "ibm_container_vpc_cluster" "vpc_cluster_data" {
  count             = var.cluster_name_id != null ? 1 : 0
  name              = var.cluster_name_id
  resource_group_id = module.resource_group.resource_group_id
}

##############################################################################
# Cluster kubeconfig
##############################################################################

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = local.cluster_id
  resource_group_id = module.resource_group.resource_group_id
  admin             = true
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
}

resource "time_sleep" "wait_operators" {
  depends_on      = [data.ibm_container_cluster_config.cluster_config]
  create_duration = "60s"
}

##############################################################################
# BRS Backup & Recovery with VPEG connectivity
##############################################################################

module "backup_recovery" {
  source = "../.."
  providers = {
    ibm         = ibm
    ibm.cluster = ibm
  }

  depends_on = [time_sleep.wait_operators]

  # ---- Cluster ----
  cluster_id                   = local.cluster_id
  cluster_resource_group_id    = module.resource_group.resource_group_id
  cluster_config_endpoint_type = var.cluster_config_endpoint_type
  kube_type                    = "kubernetes"
  connection_env_type          = "kIksVpc"
  ibmcloud_api_key             = var.ibmcloud_api_key
  region                       = var.region
  dsc_storage_class            = "ibmc-vpc-block-metro-5iops-tier"
  dsc_worker_pool_zones        = 1 # single-zone cluster
  add_dsc_rules_to_cluster_sg  = false
  enable_auto_protect          = false

  # ---- BRS instance ----
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_instance_name         = "${var.prefix}-brs"
  brs_connection_name       = "${var.prefix}-brs-connection"
  brs_create_new_connection = true

  # ---- Endpoint & VPEG connectivity ----
  # brs_endpoint_type = "public" lets Terraform (running on your workstation or
  # in CI) reach the BRS control plane directly to create resources.
  #
  # The DSC Helm chart does NOT use this setting for its own BRS communication.
  # The chart reads cluster_endpoint from the registration token JWT, which BRS
  # always encodes as the BRS private hostname. Setting create_brs_vpe = true
  # creates a VPE Gateway in the cluster VPC so that private hostname resolves
  # to a VPC-internal IP — routing DSC↔BRS traffic through the IBM backbone
  # instead of the IBM Cloud Service Endpoint (CSE).
  brs_endpoint_type = "public" # Terraform uses public; DSC traffic routes via VPE automatically
  create_brs_vpe    = true

  # When creating a new cluster the root module cannot auto-discover subnets at
  # plan time (worker_pools is empty until apply). Supply the explicit subnet
  # created above so ibm_is_subnet count is always known during plan.
  # For an existing cluster (cluster_name_id != null) these are null/[] and the
  # root module falls back to auto-discovery via the cluster data source.
  vpc_id      = local.explicit_vpc_id
  vpc_subnets = local.explicit_vpc_subnets

  brs_source_account_id = var.brs_source_account_id # null = same-account

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
