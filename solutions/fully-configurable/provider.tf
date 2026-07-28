########################################################################################################################
# Provider config
########################################################################################################################

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  visibility       = var.provider_visibility
}

provider "kubernetes" {
  host                   = data.ibm_container_cluster_config.cluster_config.host
  client_certificate     = data.ibm_container_cluster_config.cluster_config.admin_certificate
  client_key             = data.ibm_container_cluster_config.cluster_config.admin_key
  cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
}

provider "kubernetes" {
  alias                  = "target"
  host                   = (var.deployment_mode == "connected_component" || (var.deployment_mode == "full_backup_recovery" && var.recovery_type == "cross-cluster")) ? data.ibm_container_cluster_config.target_cluster_config[0].host : data.ibm_container_cluster_config.cluster_config.host
  client_certificate     = (var.deployment_mode == "connected_component" || (var.deployment_mode == "full_backup_recovery" && var.recovery_type == "cross-cluster")) ? data.ibm_container_cluster_config.target_cluster_config[0].admin_certificate : data.ibm_container_cluster_config.cluster_config.admin_certificate
  client_key             = (var.deployment_mode == "connected_component" || (var.deployment_mode == "full_backup_recovery" && var.recovery_type == "cross-cluster")) ? data.ibm_container_cluster_config.target_cluster_config[0].admin_key : data.ibm_container_cluster_config.cluster_config.admin_key
  cluster_ca_certificate = (var.deployment_mode == "connected_component" || (var.deployment_mode == "full_backup_recovery" && var.recovery_type == "cross-cluster")) ? data.ibm_container_cluster_config.target_cluster_config[0].ca_certificate : data.ibm_container_cluster_config.cluster_config.ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = data.ibm_container_cluster_config.cluster_config.host
    client_certificate     = data.ibm_container_cluster_config.cluster_config.admin_certificate
    client_key             = data.ibm_container_cluster_config.cluster_config.admin_key
    cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
  }
}

provider "helm" {
  alias = "target"
  kubernetes = {
    host                   = (var.deployment_mode == "connected_component" || (var.deployment_mode == "full_backup_recovery" && var.recovery_type == "cross-cluster")) ? data.ibm_container_cluster_config.target_cluster_config[0].host : data.ibm_container_cluster_config.cluster_config.host
    client_certificate     = (var.deployment_mode == "connected_component" || (var.deployment_mode == "full_backup_recovery" && var.recovery_type == "cross-cluster")) ? data.ibm_container_cluster_config.target_cluster_config[0].admin_certificate : data.ibm_container_cluster_config.cluster_config.admin_certificate
    client_key             = (var.deployment_mode == "connected_component" || (var.deployment_mode == "full_backup_recovery" && var.recovery_type == "cross-cluster")) ? data.ibm_container_cluster_config.target_cluster_config[0].admin_key : data.ibm_container_cluster_config.cluster_config.admin_key
    cluster_ca_certificate = (var.deployment_mode == "connected_component" || (var.deployment_mode == "full_backup_recovery" && var.recovery_type == "cross-cluster")) ? data.ibm_container_cluster_config.target_cluster_config[0].ca_certificate : data.ibm_container_cluster_config.cluster_config.ca_certificate
  }
}
