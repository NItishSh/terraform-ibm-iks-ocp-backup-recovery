##############################################################################
# Terraform Providers
##############################################################################

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
}

##############################################################################
# Kubernetes Provider for Source Cluster
##############################################################################

provider "kubernetes" {
  alias                  = "source"
  host                   = data.ibm_container_cluster_config.source_cluster_config.host
  client_certificate     = data.ibm_container_cluster_config.source_cluster_config.admin_certificate
  client_key             = data.ibm_container_cluster_config.source_cluster_config.admin_key
  cluster_ca_certificate = data.ibm_container_cluster_config.source_cluster_config.ca_certificate
}

##############################################################################
# Helm Provider for Source Cluster
##############################################################################

provider "helm" {
  alias = "source"

  kubernetes = {
    host                   = data.ibm_container_cluster_config.source_cluster_config.host
    client_certificate     = data.ibm_container_cluster_config.source_cluster_config.admin_certificate
    client_key             = data.ibm_container_cluster_config.source_cluster_config.admin_key
    cluster_ca_certificate = data.ibm_container_cluster_config.source_cluster_config.ca_certificate
  }
}

##############################################################################
# Kubernetes Provider for Target Cluster
##############################################################################

provider "kubernetes" {
  alias                  = "target"
  host                   = data.ibm_container_cluster_config.target_cluster_config.host
  client_certificate     = data.ibm_container_cluster_config.target_cluster_config.admin_certificate
  client_key             = data.ibm_container_cluster_config.target_cluster_config.admin_key
  cluster_ca_certificate = data.ibm_container_cluster_config.target_cluster_config.ca_certificate
}

##############################################################################
# Helm Provider for Target Cluster
##############################################################################

provider "helm" {
  alias = "target"

  kubernetes = {
    host                   = data.ibm_container_cluster_config.target_cluster_config.host
    client_certificate     = data.ibm_container_cluster_config.target_cluster_config.admin_certificate
    client_key             = data.ibm_container_cluster_config.target_cluster_config.admin_key
    cluster_ca_certificate = data.ibm_container_cluster_config.target_cluster_config.ca_certificate
  }
}
