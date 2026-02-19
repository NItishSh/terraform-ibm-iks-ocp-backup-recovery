##############################################################################
# Resource Group
##############################################################################
module "resource_group" {
  source                       = "terraform-ibm-modules/resource-group/ibm"
  version                      = "1.4.7"
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

########################################################################################################################
# VPC + Subnet + Public Gateway
#
# NOTE: This is a very simple VPC with single subnet in a single zone with a public gateway enabled, that will allow
# all traffic ingress/egress by default.
# For production use cases this would need to be enhanced by adding more subnets and zones for resiliency, and
# ACLs/Security Groups for network security.
########################################################################################################################

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

########################################################################################################################
# OCP VPC cluster (single zone)
########################################################################################################################

locals {
  cluster_vpc_subnets = var.cluster_name_id == null ? {
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
  count                = var.cluster_name_id == null ? 1 : 0
  source               = "terraform-ibm-modules/base-ocp-vpc/ibm"
  version              = "3.78.7"
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

data "ibm_container_vpc_cluster" "cluster" {
  count             = var.cluster_name_id == null ? 0 : 1
  name              = var.cluster_name_id != null ? var.cluster_name_id : module.ocp_base[0].cluster_name
  resource_group_id = module.resource_group.resource_group_id
}

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = var.cluster_name_id == null ? module.ocp_base[0].cluster_id : data.ibm_container_vpc_cluster.cluster[0].name
  resource_group_id = module.resource_group.resource_group_id
  admin             = true
}

# Sleep to allow RBAC sync on cluster
resource "time_sleep" "wait_operators" {
  depends_on      = [data.ibm_container_cluster_config.cluster_config]
  create_duration = "60s"
}

########################################################################################################################
# Backup & Recovery Service (BRS)
########################################################################################################################

module "backup_recovery_instance" {
  source                = "terraform-ibm-modules/backup-recovery/ibm"
  version               = "v1.3.0"
  region                = var.region
  resource_group_id     = module.resource_group.resource_group_id
  ibmcloud_api_key      = var.ibmcloud_api_key
  tags                  = var.resource_tags
  instance_name         = "${var.prefix}-brs-instance"
  connection_name       = "${var.prefix}-brs-connection-RoksVpc"
  create_new_connection = true
  create_new_instance   = true
}


########################################################################################################################
# Backup & Recovery for IKS/ROKS with Data Source Connector
########################################################################################################################


module "backup_recover_protect_ocp" {
  source                       = "../.."
  cluster_id                   = var.cluster_name_id == null ? module.ocp_base[0].cluster_id : data.ibm_container_vpc_cluster.cluster[0].id
  cluster_resource_group_id    = module.resource_group.resource_group_id
  cluster_config_endpoint_type = "private"
  add_dsc_rules_to_cluster_sg  = false
  kube_type                    = "openshift"
  ibmcloud_api_key             = var.ibmcloud_api_key
  # enable_auto_protect is set to false to avoid issues when running terraform pipelines. in production, this should be set to true.
  enable_auto_protect = false
  # --- B&R Instance ---
  brs_endpoint_type   = "public"
  brs_instance_crn    = module.backup_recovery_instance.brs_instance_crn
  brs_connection_name = module.backup_recovery_instance.connection_name
  # --- Backup Policy ---
  policy = {
    name = "${var.prefix}-retention"
    schedule = {
      unit      = "Minutes"
      frequency = 30
    }
    retention = {
      duration = 1
      unit     = "Days"
    }
    use_default_backup_target = true
  }
}
