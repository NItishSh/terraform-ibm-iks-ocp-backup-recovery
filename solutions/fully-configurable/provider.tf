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

provider "helm" {
  kubernetes = {
    host                   = data.ibm_container_cluster_config.cluster_config.host
    client_certificate     = data.ibm_container_cluster_config.cluster_config.admin_certificate
    client_key             = data.ibm_container_cluster_config.cluster_config.admin_key
    cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
  }
  registries = [
    { url = "oci://stg.icr.io", username = "iamapikey", password = var.ibmcloud_api_key }
  ]
}
