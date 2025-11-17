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

########################################################################################################################
# OCP VPC cluster (single zone)
########################################################################################################################

locals {
  cluster_vpc_subnets = {
    default = [
      {
        id         = ibm_is_subnet.subnet_zone_1.id
        cidr_block = ibm_is_subnet.subnet_zone_1.ipv4_cidr_block
        zone       = ibm_is_subnet.subnet_zone_1.zone
      }
    ]
  }

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
  source               = "terraform-ibm-modules/base-ocp-vpc/ibm"
  version              = "3.71.3"
  resource_group_id    = module.resource_group.resource_group_id
  region               = var.region
  tags                 = var.resource_tags
  cluster_name         = var.prefix
  force_delete_storage = true
  vpc_id               = ibm_is_vpc.vpc.id
  vpc_subnets          = local.cluster_vpc_subnets
  ocp_version          = var.ocp_version
  worker_pools         = local.worker_pools
  access_tags          = var.access_tags
  ocp_entitlement      = var.ocp_entitlement
}

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = module.ocp_base.cluster_id
  resource_group_id = module.resource_group.resource_group_id
  admin             = true
}

########################################################################################################################
# Backup & Recovery Service (BRS) Module
########################################################################################################################

module "backup_recovery_instance" {
  source            = "terraform-ibm-modules/backup-recovery/ibm"
  version           = "v1.0.0"
  region            = var.region
  resource_group_id = module.resource_group.resource_group_id
  ibmcloud_api_key  = var.ibmcloud_api_key
  tags              = var.resource_tags
}


########################################################################################################################
# Backup & Recovery for IKS/ROKS with Data Source Connector
########################################################################################################################


module "backup_recover_protect_ocp" {
  source         = "../.."
  resource_group = var.resource_group
  # --- DSC Helm Chart ---
  dsc = {
    release_name       = "dsc"
    chart_name         = "cohesity-dsc-chart"
    chart_repository   = "oci://icr.io/ext/brs/"
    namespace          = "dsc"
    create_namespace   = true
    chart_version      = "7.2.15-release-20250721-6aa24701"
    registration_token = module.backup_recovery_instance.registration_token
    replica_count      = 1
    timeout            = 1800

    image = {
      namespace  = "ext"
      repository = "brs/cohesity-data-source-connector_7.2.15-release-20250721"
      tag        = "6aa24701"
      pullPolicy = "IfNotPresent"
    }
  }

  # --- B&R Instance ---
  brsintance = {
    guid          = module.backup_recovery_instance.brs_instance_guid
    region        = var.region
    endpoint_type = "public"
    tenant_id     = module.backup_recovery_instance.tenant_id
  }

  # --- Cluster Registration ---
  cluster_id    = module.ocp_base.cluster_id
  connection_id = module.backup_recovery_instance.connection_id

  registration = {
    name = module.ocp_base.cluster_name
    cluster = {
      resource_group_id = module.resource_group.resource_group_id
      endpoint          = module.ocp_base.private_service_endpoint_url
      distribution      = "kROKS"
      images = {
        data_mover              = "icr.io/ext/brs/cohesity-datamover:7.2.15-p2"
        velero                  = "icr.io/ext/brs/velero:7.2.15-p2"
        velero_aws_plugin       = "icr.io/ext/brs/velero-plugin-for-aws:7.2.15-p2"
        velero_openshift_plugin = "icr.io/ext/brs/velero-plugin-for-openshift:7.2.15-p2"
        init_container          = ""
      }
    }
  }

  # --- Backup Policy ---
  policy = {
    name = "daily-with-weekly-lock"

    schedule = {
      unit      = "Hours"
      frequency = 6
      # Optional layered schedule
      week_schedule = {
        day_of_week = ["Sunday"]
      }
    }

    retention = {
      duration = 4
      unit     = "Weeks"
    }

    use_default_backup_target = true
  }
}