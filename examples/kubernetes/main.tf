##############################################################################
# Resource Group
##############################################################################
module "resource_group" {
  source                       = "terraform-ibm-modules/resource-group/ibm"
  version                      = "1.4.0"
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
  name                      = "${var.prefix}-vpc"
  resource_group            = module.resource_group.resource_group_id
  address_prefix_management = "auto"
  tags                      = var.resource_tags
}

resource "ibm_is_public_gateway" "gateway" {
  name           = "${var.prefix}-gateway-1"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = module.resource_group.resource_group_id
  zone           = "${var.region}-1"
}

resource "ibm_is_subnet" "subnet_zone_1" {
  name                     = "${var.prefix}-subnet-1"
  vpc                      = ibm_is_vpc.vpc.id
  resource_group           = module.resource_group.resource_group_id
  zone                     = "${var.region}-1"
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.gateway.id
}

##############################################################################
# Create a Kubernetes cluster with 3 worker nodes
##############################################################################

resource "ibm_container_vpc_cluster" "cluster" {
  name              = "${var.prefix}-cluster"
  vpc_id            = ibm_is_vpc.vpc.id
  flavor            = "bx2.4x16"
  resource_group_id = module.resource_group.resource_group_id
  worker_count      = 2
  zones {
    subnet_id = ibm_is_subnet.subnet_zone_1.id
    name      = "${var.region}-1"
  }
  wait_till = "IngressReady"
  # Allows outbound internet access for your workspace runs to be able to pull terraform providers from the internet. [Learn more](https://cloud.ibm.com/docs/schematics?topic=schematics-agent-infrastructure-overview#agents-infra-workspace)
  # If you want to deploy a fully private cluster, you must configure private registries so Terraform providers can be downloaded. [Learn more](https://cloud.ibm.com/docs/schematics?topic=schematics-agent-registry-overview&interface=terraform)
  disable_outbound_traffic_protection = true
}

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = ibm_container_vpc_cluster.cluster.id
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
  version               = "v1.1.0"
  region                = var.region
  resource_group_id     = module.resource_group.resource_group_id
  ibmcloud_api_key      = var.ibmcloud_api_key
  tags                  = var.resource_tags
  instance_name         = "${var.prefix}-brs-instance"
  connection_name       = "${var.prefix}-brs-connection"
  create_new_connection = true
  create_new_instance   = true
}


########################################################################################################################
# Backup & Recovery for IKS/ROKS with Data Source Connector
########################################################################################################################


module "backup_recover_protect_ocp" {
  source                    = "../.."
  cluster_id                = ibm_container_vpc_cluster.cluster.id
  cluster_resource_group_id = module.resource_group.resource_group_id
  dsc_registration_token    = module.backup_recovery_instance.registration_token
  kube_type                 = "kubernetes"
  connection_id             = module.backup_recovery_instance.connection_id
  # --- B&R Instance ---
  brs_instance_guid   = module.backup_recovery_instance.brs_instance_guid
  brs_instance_region = var.region
  brs_endpoint_type   = "public"
  brs_tenant_id       = module.backup_recovery_instance.tenant_id
  registration_name   = ibm_container_vpc_cluster.cluster.name
  # --- Backup Policy ---
  policy = {
    name = "${var.prefix}-retention"
    schedule = {
      unit      = "Hours"
      frequency = 6
    }
    retention = {
      duration = 4
      unit     = "Weeks"
    }
    use_default_backup_target = true
  }
}
