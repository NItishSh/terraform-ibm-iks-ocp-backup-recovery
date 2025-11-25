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
# Data Sources for Existing OCP/ROKS cluster
########################################################################################################################

data "ibm_container_vpc_cluster" "existing_cluster" {
  name              = var.existing_cluster_name
  resource_group_id = module.resource_group.resource_group_id # Assumes cluster is in the specified resource group
}


# This data source gets the cluster configuration details needed for the BRS module
data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = data.ibm_container_vpc_cluster.existing_cluster.id
  resource_group_id = module.resource_group.resource_group_id
  admin             = true
}

########################################################################################################################
# Backup & Recovery Service (BRS)
########################################################################################################################

module "backup_recovery_instance" {
  source            = "terraform-ibm-modules/backup-recovery/ibm"
  version           = "v1.1.0"
  region            = var.region
  instance_name     = "pentest-dnd-brs-roks"
  connection_name   = "pentest-dnd-brs-roks"
  resource_group_id = module.resource_group.resource_group_id
  ibmcloud_api_key  = var.ibmcloud_api_key
  tags              = var.resource_tags
}


########################################################################################################################
# Backup & Recovery for IKS/ROKS with Data Source Connector
########################################################################################################################


module "backup_recover_protect_ocp" {
  source = "../.."
  # Use the ID of the existing cluster data source
  cluster_id                = data.ibm_container_vpc_cluster.existing_cluster.id
  cluster_resource_group_id = module.resource_group.resource_group_id
  dsc_registration_token    = module.backup_recovery_instance.registration_token
  kube_type                 = "ROKS"
  connection_id             = module.backup_recovery_instance.connection_id
  # --- B&R Instance ---
  brs_instance_guid   = module.backup_recovery_instance.brs_instance_guid
  brs_instance_region = var.region
  brs_endpoint_type   = "public"
  brs_tenant_id       = module.backup_recovery_instance.tenant_id
  # Use the name of the existing cluster data source
  registration_name = data.ibm_container_vpc_cluster.existing_cluster.name
  registration_images = {
    data_mover              = "icr.io/ext/brs/cohesity-datamover:7.2.15-p2"
    velero                  = "icr.io/ext/brs/velero:7.2.15-p2"
    velero_aws_plugin       = "icr.io/ext/brs/velero-plugin-for-aws:7.2.15-p2"
    velero_openshift_plugin = "icr.io/ext/brs/velero-plugin-for-openshift:7.2.15-p2"
  }
  # --- Backup Policy ---
  policy = {
    name = "daily-with-monthly-retention"
    schedule = {
      unit      = "Hours"
      frequency = 24
    }
    retention = {
      duration = 4
      unit     = "Weeks"
    }
    use_default_backup_target = true
  }
}
