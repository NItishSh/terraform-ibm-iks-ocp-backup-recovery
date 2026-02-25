
##############################################################################
# Resource Group
##############################################################################

module "resource_group" {
  source  = "terraform-ibm-modules/resource-group/ibm"
  version = "1.4.7"
  # if an existing resource group is not set (null) create a new one using prefix
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

########################################################################################################################
# Classic Infrastructure: VLANs
########################################################################################################################

resource "ibm_network_vlan" "public_vlan" {
  count      = var.cluster_name_id == null ? 1 : 0
  datacenter = var.datacenter
  type       = "PUBLIC"
}

resource "ibm_network_vlan" "private_vlan" {
  count           = var.cluster_name_id == null ? 1 : 0
  datacenter      = var.datacenter
  type            = "PRIVATE"
  router_hostname = replace(ibm_network_vlan.public_vlan[0].router_hostname, "fcr", "bcr")
}

##############################################################################
# Create a Classic Kubernetes cluster with 2 worker nodes
##############################################################################

# Lookup the current default kube version
data "ibm_container_cluster_versions" "cluster_versions" {}

locals {
  default_version = data.ibm_container_cluster_versions.cluster_versions.default_kube_version
}

resource "ibm_container_cluster" "cluster" {
  #checkov:skip=CKV2_IBM_7:Public endpoint is required for testing purposes
  count                = var.cluster_name_id == null ? 1 : 0
  name                 = "${var.prefix}-cluster"
  datacenter           = var.datacenter
  default_pool_size    = 2
  hardware             = "shared"
  kube_version         = local.default_version
  force_delete_storage = true
  machine_type         = "b3c.4x16"
  public_vlan_id       = ibm_network_vlan.public_vlan[0].id
  private_vlan_id      = ibm_network_vlan.private_vlan[0].id
  wait_till            = "Normal"
  resource_group_id    = module.resource_group.resource_group_id
  tags                 = var.resource_tags

  timeouts {
    delete = "2h"
    create = "3h"
  }
}

data "ibm_container_cluster" "cluster" {
  count             = var.cluster_name_id != null ? 1 : 0
  name              = var.cluster_name_id
  resource_group_id = module.resource_group.resource_group_id
}

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = var.cluster_name_id != null ? data.ibm_container_cluster.cluster[0].id : ibm_container_cluster.cluster[0].id
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
  cluster_id                   = var.cluster_name_id != null ? data.ibm_container_cluster.cluster[0].id : ibm_container_cluster.cluster[0].id
  cluster_resource_group_id    = module.resource_group.resource_group_id
  cluster_config_endpoint_type = "private"
  add_dsc_rules_to_cluster_sg  = false
  kube_type                    = "kubernetes"
  ibmcloud_api_key             = var.ibmcloud_api_key
  enable_auto_protect          = false
  # --- B&R Instance ---
  brs_endpoint_type         = "public"
  brs_instance_name         = "${var.prefix}-brs-instance"
  brs_connection_name       = "${var.prefix}-brs-connection-IksClassic"
  brs_create_new_connection = true
  region                    = var.region
  connection_env_type       = "kIksClassic"
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
  access_tags   = var.access_tags
  resource_tags = var.resource_tags
}
