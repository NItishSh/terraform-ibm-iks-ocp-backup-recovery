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
  host                   = var.enable_recovery && var.recovery_type == "cross-cluster" ? data.ibm_container_cluster_config.target_cluster_config[0].host : data.ibm_container_cluster_config.cluster_config.host
  client_certificate     = var.enable_recovery && var.recovery_type == "cross-cluster" ? data.ibm_container_cluster_config.target_cluster_config[0].admin_certificate : data.ibm_container_cluster_config.cluster_config.admin_certificate
  client_key             = var.enable_recovery && var.recovery_type == "cross-cluster" ? data.ibm_container_cluster_config.target_cluster_config[0].admin_key : data.ibm_container_cluster_config.cluster_config.admin_key
  cluster_ca_certificate = var.enable_recovery && var.recovery_type == "cross-cluster" ? data.ibm_container_cluster_config.target_cluster_config[0].ca_certificate : data.ibm_container_cluster_config.cluster_config.ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = data.ibm_container_cluster_config.cluster_config.host
    client_certificate     = data.ibm_container_cluster_config.cluster_config.admin_certificate
    client_key             = data.ibm_container_cluster_config.cluster_config.admin_key
    cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
  }
  registries = [
    { url = "oci://${var.dsc_registry}", username = "iamapikey", password = var.ibmcloud_api_key }
  ]
}

provider "helm" {
  alias = "target"
  kubernetes = {
    host                   = var.enable_recovery && var.recovery_type == "cross-cluster" ? data.ibm_container_cluster_config.target_cluster_config[0].host : data.ibm_container_cluster_config.cluster_config.host
    client_certificate     = var.enable_recovery && var.recovery_type == "cross-cluster" ? data.ibm_container_cluster_config.target_cluster_config[0].admin_certificate : data.ibm_container_cluster_config.cluster_config.admin_certificate
    client_key             = var.enable_recovery && var.recovery_type == "cross-cluster" ? data.ibm_container_cluster_config.target_cluster_config[0].admin_key : data.ibm_container_cluster_config.cluster_config.admin_key
    cluster_ca_certificate = var.enable_recovery && var.recovery_type == "cross-cluster" ? data.ibm_container_cluster_config.target_cluster_config[0].ca_certificate : data.ibm_container_cluster_config.cluster_config.ca_certificate
  }
  registries = [
    { url = "oci://${var.dsc_registry}", username = "iamapikey", password = var.ibmcloud_api_key }
  ]
}
