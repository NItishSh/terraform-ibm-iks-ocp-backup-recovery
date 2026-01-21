########################################################################################################################
# Provider config
########################################################################################################################

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
}

provider "kubernetes" {
  host                   = data.ibm_container_cluster_config.cluster_config.host
  token                  = data.ibm_container_cluster_config.cluster_config.token
  cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = data.ibm_container_cluster_config.cluster_config.host
    token                  = data.ibm_container_cluster_config.cluster_config.token
    cluster_ca_certificate = data.ibm_container_cluster_config.cluster_config.ca_certificate
  }
  registries = [
    { url = "oci://icr.io", username = "iamapikey", password = var.ibmcloud_api_key }
  ]
}
