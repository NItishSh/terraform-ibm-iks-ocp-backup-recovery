# Retrieve information about an existing VPC cluster
data "ibm_container_cluster_config" "cluster_config" {
  cluster_name_id   = var.cluster_id
  resource_group_id = var.cluster_resource_group_id
  config_dir        = "${path.module}/kubeconfig"
  endpoint_type     = var.cluster_config_endpoint_type != "default" ? var.cluster_config_endpoint_type : null
}


########################################################################################################################
# Backup & Recovery for IKS/ROKS with Data Source Connector
########################################################################################################################


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
  brs_instance_crn          = var.brs_instance_crn
  brs_connection_name       = var.brs_connection_name
  brs_create_new_connection = var.brs_create_new_connection
  brs_instance_name         = var.brs_instance_name
  region                    = var.region
  # --- Backup Policy ---
  policy            = var.policy
  wait_till         = var.wait_till
  wait_till_timeout = var.wait_till_timeout
  # --- Data Source Connector (DSC) ---
  dsc_chart_uri     = var.dsc_chart_uri
  dsc_image_version = var.dsc_image_version
  dsc_name          = var.dsc_name
  dsc_replicas      = var.dsc_replicas
  dsc_namespace     = var.dsc_namespace
  dsc_helm_timeout  = var.dsc_helm_timeout
  # --- Registration Settings ---
  registration_images = var.registration_images
  enable_auto_protect = var.enable_auto_protect
  # --- Resource Tags ---
  resource_tags = var.resource_tags
  access_tags   = var.access_tags
}
