##############################################################################
# Resource Group
##############################################################################

module "resource_group" {
  source                       = "terraform-ibm-modules/resource-group/ibm"
  version                      = "1.6.0"
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

########################################################################################################################
# OCP Cluster
########################################################################################################################

locals {
  cluster_vpc_subnets = (var.cluster_name_id == null && !var.classic_cluster) ? {
    default = [
      {
        id         = ibm_is_subnet.subnet_zone_1[0].id
        cidr_block = ibm_is_subnet.subnet_zone_1[0].ipv4_cidr_block
        zone       = ibm_is_subnet.subnet_zone_1[0].zone
      }
    ]
  } : {}

  worker_pools = [
    {
      subnet_prefix    = "default"
      pool_name        = "default" # ibm_container_vpc_cluster automatically names default pool "default" (See https://github.com/IBM-Cloud/terraform-provider-ibm/issues/2849)
      machine_type     = "bx2.4x16"
      operating_system = "RHCOS"
      workers_per_zone = 2 # minimum of 2 is allowed when using single zone
    }
  ]
}

module "ocp_base" {
  count                = var.cluster_name_id == null && !var.classic_cluster ? 1 : 0
  source               = "terraform-ibm-modules/base-ocp-vpc/ibm"
  version              = "3.86.0"
  resource_group_id    = module.resource_group.resource_group_id
  region               = var.region
  tags                 = var.resource_tags
  cluster_name         = "${var.prefix}-cluster"
  force_delete_storage = true
  vpc_id               = ibm_is_vpc.vpc[0].id
  vpc_subnets          = local.cluster_vpc_subnets
  ocp_version          = var.ocp_version
  worker_pools         = local.worker_pools
  access_tags          = var.access_tags
  ocp_entitlement      = var.ocp_entitlement
}

# Lookup the current default OpenShift version
data "ibm_container_cluster_versions" "cluster_versions" {}

locals {
  default_version = data.ibm_container_cluster_versions.cluster_versions.default_openshift_version
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
  entitlement          = var.ocp_entitlement

  timeouts {
    delete = "2h"
    create = "3h"
  }

  lifecycle {
    ignore_changes = [tags]
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

locals {
  cluster_id = var.cluster_name_id != null ? (var.classic_cluster ? data.ibm_container_cluster.classic_cluster_data[0].id : data.ibm_container_vpc_cluster.vpc_cluster_data[0].name) : (var.classic_cluster ? ibm_container_cluster.classic_cluster[0].id : module.ocp_base[0].cluster_id)

  cluster_name_id_for_config = var.cluster_name_id != null ? (var.classic_cluster ? data.ibm_container_cluster.classic_cluster_data[0].id : data.ibm_container_vpc_cluster.vpc_cluster_data[0].name) : (var.classic_cluster ? ibm_container_cluster.classic_cluster[0].id : module.ocp_base[0].cluster_id)
}

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = local.cluster_name_id_for_config
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


module "backup_recover_protect_ocp" {
  source                       = "../.."
  cluster_id                   = local.cluster_id
  cluster_resource_group_id    = module.resource_group.resource_group_id
  cluster_config_endpoint_type = "private"
  add_dsc_rules_to_cluster_sg  = false
  kube_type                    = "openshift"
  ibmcloud_api_key             = var.ibmcloud_api_key
  # enable_auto_protect is set to false to avoid issues when running terraform pipelines. in production, this should be set to true.
  enable_auto_protect      = false
  external_kubeconfig_path = data.ibm_container_cluster_config.cluster_config.config_file_path
  # --- B&R Instance ---
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_endpoint_type         = "public"
  brs_instance_name         = "${var.prefix}-brs-instance"
  brs_connection_name       = "${var.prefix}-brs-connection-${var.classic_cluster ? "RoksClassic" : "RoksVpc"}"
  brs_create_new_connection = true
  region                    = var.region
  connection_env_type       = var.classic_cluster ? "kRoksClassic" : "kRoksVpc"
  dsc_storage_class         = var.dsc_storage_class == null ? (var.classic_cluster ? "ibmc-block-silver" : "ibmc-vpc-block-metro-5iops-tier") : var.dsc_storage_class
  # --- Backup Policy ---
  auto_protect_policy_name = "${var.prefix}-retention"
  access_tags              = var.access_tags
  resource_tags            = var.resource_tags
  # Policies are now created in the BRS module
  policies = [
    {
      name              = "${var.prefix}-retention"
      create_new_policy = true
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
  # Disable automatic tag addition to prevent drift with ocp_base module
  add_cluster_tags = false
}
