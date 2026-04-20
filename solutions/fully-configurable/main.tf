# Retrieve information about an existing VPC cluster
# Wait for cluster to be ready before downloading config
resource "terraform_data" "wait_for_cluster_ready" {
  triggers_replace = {
    cluster_id     = var.cluster_id
    endpoint_type  = var.cluster_config_endpoint_type
    resource_group = var.cluster_resource_group_id
  }

  provisioner "local-exec" {
    command     = "${path.module}/../../scripts/wait_for_cluster_ready.sh '${var.cluster_id}' '${var.cluster_resource_group_id}'"
    interpreter = ["/bin/bash", "-c"]
  }
}

data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  config_dir        = "${path.module}/kubeconfig"
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
  admin             = true

  depends_on = [terraform_data.wait_for_cluster_ready]
}

module "existing_brs_crn_parser" {
  count   = var.existing_brs_instance_crn != null ? 1 : 0
  source  = "terraform-ibm-modules/common-utilities/ibm//modules/crn-parser"
  version = "1.5.0"
  crn     = var.existing_brs_instance_crn
}

locals {
  region = var.existing_brs_instance_crn != null ? module.existing_brs_crn_parser[0].region : var.region
}

module "protect_cluster" {
  source                       = "../.."
  cluster_id                   = var.cluster_id
  cluster_resource_group_id    = var.cluster_resource_group_id
  cluster_config_endpoint_type = var.cluster_config_endpoint_type
  add_dsc_rules_to_cluster_sg  = var.add_dsc_rules_to_cluster_sg
  kube_type                    = var.kube_type
  ibmcloud_api_key             = var.ibmcloud_api_key
  # --- BRS Instance Details---
  brs_endpoint_type         = var.brs_endpoint_type
  existing_brs_instance_crn = var.existing_brs_instance_crn
  brs_instance_name         = var.brs_instance_name
  # --- BRS Connection Details---
  brs_connection_name       = var.brs_connection_name
  brs_create_new_connection = var.brs_create_new_connection
  region                    = local.region
  connection_env_type       = var.connection_env_type
  # --- Backup Policy ---
  auto_protect_policy_name = var.auto_protect_policy_name
  wait_till                = var.wait_till
  wait_till_timeout        = var.wait_till_timeout
  # --- Data Source Connector (DSC) ---
  dsc_chart_uri          = var.dsc_chart_uri
  dsc_image_version      = var.dsc_image_version
  dsc_name               = var.dsc_name
  dsc_replicas           = var.dsc_replicas
  dsc_namespace          = var.dsc_namespace
  dsc_helm_timeout       = var.dsc_helm_timeout
  dsc_storage_class      = var.dsc_storage_class
  create_dsc_worker_pool = var.create_dsc_worker_pool
  # --- Registration Settings ---
  registration_images = var.registration_images
  enable_auto_protect = var.enable_auto_protect
  # --- Policies ---
  policies = var.policies
  # --- Resource Tags ---
  resource_tags = var.resource_tags
  access_tags   = var.access_tags
}

########################################################################################################################
# Cleanup BRS-agent runtime resources on destroy
# BRS agent creates a namespace and ClusterRoleBinding (brs-backup-agent-<uuid>) that Terraform does not manage.
# This terraform_data resource runs a local-exec on destroy to clean them up.
#
# Cluster credentials (host, CA, cert, key) are stored in triggers at apply time so they are available
# at destroy time without any dependency on kubeconfig files on disk.
# Schematics runs refresh and destroy in separate phases/containers, so file-based kubeconfig approaches
# are unreliable. Storing credentials in triggers is the only reliable approach.
# Note: these values are already present in Terraform state via the data source; Schematics encrypts state.
########################################################################################################################
resource "terraform_data" "cleanup_brs_agent_resources" {
  triggers_replace = {
    cluster_id = var.cluster_id
    kube_host  = data.ibm_container_cluster_config.cluster_config.host
    kube_ca    = data.ibm_container_cluster_config.cluster_config.ca_certificate
    kube_cert  = data.ibm_container_cluster_config.cluster_config.admin_certificate
    kube_key   = data.ibm_container_cluster_config.cluster_config.admin_key
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/../../scripts/cleanup_brs_agent_resources_schematics.sh \"${self.triggers_replace.kube_host}\" \"${self.triggers_replace.kube_ca}\" \"${self.triggers_replace.kube_cert}\" \"${self.triggers_replace.kube_key}\""
  }

  depends_on = [
    module.protect_cluster
  ]
}
