##############################################################################
# Provider configuration — cross-account VPE example
#
# Two IBM Cloud accounts are involved:
#
#   ibm.source  (source_ibmcloud_api_key)
#     The account that owns the IKS cluster and its VPC.
#     All cluster, VPC, and VPEG resources are created here.
#
#   ibm.target  (ibmcloud_api_key)
#     The account that owns the BRS instance.
#     The BRS instance, connection, and S2S IAM authorization policy
#     are created here.  This is also the default provider alias so
#     that the root module (../.. — which creates the BRS side) runs
#     against the target account.
#
# The kubernetes and helm providers are pointed at the source-account
# cluster kubeconfig so the DSC Helm chart deploys into the right cluster.
##############################################################################

# Default provider — target (BRS) account.
# The root module (../..)'s ibm_resource_instance, ibm_backup_recovery_*,
# and ibm_iam_authorization_policy resources all use this provider.
# brs_region defaults to var.region when not set explicitly.
provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.brs_region != null ? var.brs_region : var.region
}

# Source-account provider alias — cluster / VPC account.
# Used explicitly for ibm_container_vpc_cluster, ibm_is_vpc, etc.
provider "ibm" {
  alias            = "source"
  ibmcloud_api_key = var.source_ibmcloud_api_key
  region           = var.region
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
}
