########################################################################################################################
# Provider config
#
# Two deployment modes are supported:
#
#   Same-account (source_ibmcloud_api_key = null, the default)
#     The default ibm provider and ibm.cluster both use ibmcloud_api_key.
#     BRS instance, S2S auth policy, cluster, VPC, and VPEG all live in the
#     same account.
#
#   Cross-account (source_ibmcloud_api_key set)
#     ibm          → target account (ibmcloud_api_key)
#                    BRS instance, connection, S2S IAM authorization policy.
#     ibm.cluster  → source account (source_ibmcloud_api_key)
#                    Cluster, VPC, VPEG, DSC worker pool, Helm chart.
#
# The kubernetes and helm providers always point at the source-account cluster
# kubeconfig so the DSC Helm chart is deployed into the correct cluster.
########################################################################################################################

# Default provider — target (BRS) account, or only account in same-account mode.
provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  visibility       = var.provider_visibility
}

# Cluster provider alias — source (cluster/VPC) account.
# When source_ibmcloud_api_key is null (same-account), this falls back to
# ibmcloud_api_key so the alias is always valid regardless of deployment mode.
provider "ibm" {
  alias            = "cluster"
  ibmcloud_api_key = var.source_ibmcloud_api_key != null ? var.source_ibmcloud_api_key : var.ibmcloud_api_key
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
